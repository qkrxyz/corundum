const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // root module
    const root = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // submodules & tests
    const test_step = b.step("test", "Run unit tests");

    const unit_tests = b.addTest(.{
        .name = "corundum",
        .root_module = root,
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    try modules(b, root, run_unit_tests);

    // templates
    try generate(
        b,
        root,
        test_step,
        .{
            .directory = "templates",
            .function_name = "templates",
            .type_name = "template.Template(T)",
            .file_path = "all_templates.zig",
            .parent_name = "template",
        },
    );

    // library
    const library = b.addLibrary(.{
        .linkage = .static,
        .name = "corundum",
        .root_module = root,
    });
    b.installArtifact(library);

    // docs
    const docs_step = b.step("docs", "Generate documentation");

    const install_docs = b.addInstallDirectory(.{
        .source_dir = library.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}

fn modules(b: *std.Build, root: *std.Build.Module, tests: *std.Build.Step.Run) !void {
    var iterator = (try std.fs.cwd().openDir("src", .{ .iterate = true })).iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.indexOf(u8, entry.name, ".zig") != entry.name.len - 4) continue;
        if (std.mem.eql(u8, "root.zig", entry.name)) continue;

        try submodules(b, root, entry, "src", tests);
    }

    var modules_iterator = root.import_table.iterator();
    while (modules_iterator.next()) |module| {
        var submodules_iterator = module.value_ptr.*.import_table.iterator();

        while (submodules_iterator.next()) |submodule| {
            imports(root, submodule.value_ptr.*);
            imports(module.value_ptr.*, submodule.value_ptr.*);
        }

        imports(root, module.value_ptr.*);
    }
}

fn submodules(b: *std.Build, root: *std.Build.Module, entry: std.fs.Dir.Entry, dir: []const u8, tests: *std.Build.Step.Run) !void {
    const name = entry.name[0 .. entry.name.len - 4];

    // module
    const module = b.createModule(.{
        .root_source_file = b.path(b.pathJoin(&.{ dir, entry.name })),
        .target = root.resolved_target,
        .optimize = root.optimize,
    });

    // module tests
    const module_tests = b.addTest(.{
        .name = try std.mem.replaceOwned(u8, b.allocator, name, "/", "."),
        .root_module = module,
        .target = root.resolved_target,
        .optimize = root.optimize orelse .Debug,
    });
    const run_module_tests = b.addRunArtifact(module_tests);
    tests.step.dependOn(&run_module_tests.step);

    root.addImport(name, module);

    // submodules
    const dir_path = b.pathJoin(&.{ dir, entry.name[0 .. entry.name.len - 4] });

    var iterator = (std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return).iterate();
    while (try iterator.next()) |subentry| {
        if (subentry.kind == .directory) try submodules(b, module, subentry, dir_path, run_module_tests);
        if (subentry.kind != .file) continue;
        if (std.mem.indexOf(u8, entry.name, ".zig") != entry.name.len - 4) continue;

        const path = b.pathJoin(&.{ dir_path, subentry.name });
        const submodule_name = blk: {
            const first_slash = std.mem.indexOf(u8, path, "/") orelse std.mem.indexOf(u8, path, "\\") orelse unreachable;
            break :blk std.mem.replaceOwned(u8, b.allocator, path[first_slash + 1 .. path.len - 4], "\\", "/") catch unreachable;
        };

        // submodule
        const submodule = b.createModule(.{
            .root_source_file = b.path(path),
            .target = root.resolved_target,
            .optimize = root.optimize,
        });
        submodule.addImport(entry.name[0 .. entry.name.len - 4], module);
        module.addImport(submodule_name, submodule);

        // submodule test
        const submodule_tests = b.addTest(.{
            .name = try std.mem.replaceOwned(u8, b.allocator, submodule_name, "/", "."),
            .root_module = submodule,
            .target = root.resolved_target,
            .optimize = root.optimize orelse .Debug,
        });
        const run_submodule_tests = b.addRunArtifact(submodule_tests);
        run_module_tests.step.dependOn(&run_submodule_tests.step);
    }
}

pub fn generate(
    b: *std.Build,
    root: *std.Build.Module,
    tests: *std.Build.Step,
    options: struct {
        /// The directory to traverse.
        directory: []const u8,

        /// The function name to use in the generated file.
        function_name: []const u8,

        /// The type used in `std.StaticStringMap`.
        type_name: []const u8,

        /// The resulting file path.
        file_path: []const u8,

        /// The parent module name to expose this module to. This module must already exist in `root.import_table`.
        parent_name: []const u8,
    },
) !void {
    var generated = std.ArrayList(u8).init(b.allocator);

    try generated.appendSlice(b.fmt(
        \\// GENERATED FILE: DO NOT EDIT
        \\const std = @import("std");
        \\const {s} = @import("{s}");
        \\
        \\pub fn {s}(comptime T: type) type {{
        \\    return struct {{
        \\        const Self = @This();
        \\
        \\        const inner: std.StaticStringMap({s}) = .initComptime(.{{
        \\
    , .{
        options.parent_name,
        options.parent_name,
        options.function_name,
        options.type_name,
    }));

    const File = struct {
        name: []const u8,
        basename: []const u8,
        entry_path: []const u8,
    };
    var files = std.ArrayList(File).init(b.allocator);
    defer files.deinit();

    var walker = try (try std.fs.cwd().openDir(options.directory, .{ .iterate = true })).walk(b.allocator);
    defer walker.deinit();

    // collect all files
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const path = try std.mem.replaceOwned(u8, b.allocator, entry.path, "\\", "/");

        const info = File{
            .name = path[0 .. path.len - 4],
            .basename = entry.basename[0 .. entry.basename.len - 4],
            .entry_path = path,
        };
        try files.append(info);

        try generated.appendSlice(b.fmt("            .{{ \"{s}\", @import(\"{s}\").@\"{s}\"(T) }},\n", .{ info.name, info.name, info.basename }));
    }

    try generated.appendSlice(b.fmt(
        \\        }});
        \\
        \\        pub inline fn allTemplates() std.StaticStringMap({s}) {{
        \\            return inner;
        \\        }}
        \\
        \\        pub inline fn get(name: []const u8) ?{s} {{
        \\            return inner.get(name);
        \\        }}
        \\
        \\
        \\        pub inline fn filter(kind: {s}.Kind) std.StaticStringMap({s}) {{
        \\            return .initComptime(comptime blk: {{
        \\                var result: [inner.values().len]struct{{ []const u8, {s} }} = undefined;
        \\                var i = 0;
        \\
        \\                for (inner.keys(), inner.values()) |key, value| {{
        \\                    if(value == kind) {{
        \\                        result[i] = .{{ key, value }};
        \\                        i += 1;
        \\                    }}
        \\                }}
        \\                break :blk result[0..i];
        \\            }});
        \\        }}
        \\    }};
        \\}}
    , .{
        options.type_name,
        options.type_name,
        options.parent_name,
        options.type_name,
        options.type_name,
    }));

    const wf = b.addWriteFile(
        options.file_path,
        try generated.toOwnedSlice(),
    );

    const module = b.createModule(.{
        .root_source_file = try wf.getDirectory().join(b.allocator, options.file_path),
        .target = root.resolved_target,
        .optimize = root.optimize,
    });

    const module_test = b.addTest(.{
        .root_module = module,
        .name = options.directory,
        .target = root.resolved_target,
        .optimize = root.optimize orelse .Debug,
    });

    for (files.items) |info| {
        const submodule = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ options.directory, info.entry_path })),
            .target = root.resolved_target,
            .optimize = root.optimize,
        });
        imports(root, submodule);
        module.addImport(info.name, submodule);

        const submodule_test = b.addTest(.{
            .root_module = submodule,
            .name = try std.mem.replaceOwned(
                u8,
                b.allocator,
                info.name,
                "/",
                ".",
            ),
            .target = root.resolved_target,
            .optimize = root.optimize orelse .Debug,
        });

        const run_subtest = b.addRunArtifact(submodule_test);
        module_test.step.dependOn(&run_subtest.step);
    }

    if (root.import_table.get(options.parent_name)) |parent| {
        parent.addImport(options.directory, module);
        imports(root, module);
    }

    const run_module = b.addRunArtifact(module_test);

    root.owner.default_step.dependOn(&wf.step);
    tests.dependOn(&run_module.step);
}

/// Copy all imports from one module to another.
inline fn imports(source: *std.Build.Module, target: *std.Build.Module) void {
    var iterator = source.import_table.iterator();
    while (iterator.next()) |import| {
        target.addImport(import.key_ptr.*, import.value_ptr.*);
    }
}
