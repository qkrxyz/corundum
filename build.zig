const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // root module
    const root = b.createModule(.{
        .root_source_file = b.path(if (target.result.cpu.arch == .wasm32 and target.result.os.tag == .freestanding) "src/wasm.zig" else "src/root.zig"),
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
            .get_code =
            \\pub inline fn get(comptime name: Kind) blk: {
            \\    const module = inner.get(name).?;
            \\
            \\    if (@hasDecl(module, "Key")) {
            \\        break :blk struct {
            \\            key: @TypeOf(@field(module, "Key")),
            \\            module: @TypeOf(@field(module, std.enums.tagName(Kind, name).?[std.mem.lastIndexOf(u8, std.enums.tagName(Kind, name).?, "/").? + 1 ..])),
            \\        };
            \\    } else {
            \\        break :blk @TypeOf(@field(module, std.enums.tagName(Kind, name).?[std.mem.lastIndexOf(u8, std.enums.tagName(Kind, name).?, "/").? + 1 ..]));
            \\    }
            \\} {
            \\    const module = inner.get(name).?;
            \\
            \\    if(@hasDecl(module, "Key")) {
            \\        return .{
            \\            .key = @field(module, "Key"),
            \\            .module = @field(module, std.enums.tagName(Kind, name).?[std.mem.lastIndexOf(u8, std.enums.tagName(Kind, name).?, "/").? + 1 ..]),
            \\        };
            \\    } else {
            \\        return @field(module, std.enums.tagName(Kind, name).?[std.mem.lastIndexOf(u8, std.enums.tagName(Kind, name).?, "/").? + 1 ..]);
            \\    }
            \\}
            \\
            ,
            .additional_code =
            \\const Metadata = struct {
            \\    name: []const u8,
            \\    score: usize,
            \\};
            \\
            \\pub inline fn all() []Kind {
            \\    @setEvalBranchQuota((1 << 32) - 1);
            \\    comptime var kinds: [std.meta.fields(Kind).len]Kind = undefined;
            \\    comptime var length: comptime_int = 0;
            \\
            \\    inline for (std.meta.fields(Kind)) |entry| {
            \\        if(comptime std.mem.indexOf(u8, entry.name, "metadata") == null) {
            \\            const value = get(@enumFromInt(entry.value));
            \\            if (@typeInfo(@TypeOf(value)) == .@"struct") {
            \\                kinds[length] = @enumFromInt(entry.value);
            \\                length += 1;
            \\            }
            \\        }
            \\    }
            \\
            \\    comptime var metadata: [std.meta.fields(Kind).len - length]Metadata = undefined;
            \\    comptime var metadata_length: comptime_int = 0;
            \\
            \\    inline for (std.meta.fields(Kind)) |entry| {
            \\        const tag_name = @tagName(@as(Kind, @enumFromInt(entry.value)));
            \\        if (comptime std.mem.indexOf(u8, tag_name, "metadata") != null) {
            \\            const target = @field(@This(), tag_name);
            \\
            \\            metadata[metadata_length] = .{
            \\                .name = @field(target, "name"),
            \\                .score = @field(target, "score"),
            \\            };
            \\            metadata_length += 1;
            \\        }
            \\    }
            \\
            \\    const metadata_slice = metadata[0..metadata_length];
            \\
            \\    comptime std.mem.sort(
            \\        Metadata,
            \\        metadata_slice,
            \\        {},
            \\        struct {
            \\            fn sort(context: @TypeOf({}), lhs: Metadata, rhs: Metadata) bool {
            \\                _ = context;
            \\                return lhs.score > rhs.score;
            \\            }
            \\        }.sort,
            \\    );
            \\
            \\    comptime var result: [length]Kind = undefined;
            \\    comptime var result_len: comptime_int = 0;
            \\
            \\    inline for (metadata_slice) |m| {
            \\        inline for (kinds[0..length]) |kind| {
            \\            if (comptime std.mem.eql(u8, @tagName(kind)[0..std.mem.lastIndexOfScalar(u8, @tagName(kind), '/').?], m.name)) {
            \\                if(comptime std.mem.indexOfScalar(Kind, result[0..result_len], kind) == null) {
            \\                    comptime result[result_len] = kind;
            \\                    result_len += 1;
            \\                }
            \\            }
            \\        }
            \\    }
            \\
            \\    inline for (kinds[0..length]) |kind| {
            \\        if(comptime std.mem.indexOfScalar(Kind, result[0..result_len], kind) == null) {
            \\            comptime result[result_len] = kind;
            \\            result_len += 1;
            \\        }
            \\    }
            \\
            \\    return &result;
            \\}
            \\
            \\const Expression = @import("expr").Expression;
            \\
            \\pub inline fn tests(comptime kind: Kind, comptime T: type) std.StaticStringMap(*const Expression(T)) {
            \\    const module = inner.get(kind).?;
            \\    return module.TestingData(T);
            \\}
            \\
            \\pub inline fn variants(comptime kind: Kind, comptime T: type) blk: {
            \\    @setEvalBranchQuota((1 << 32) - 1);
            \\    const module = get(kind);
            \\
            \\    if (@typeInfo(@TypeOf(module)) == .@"fn") break :blk null;
            \\
            \\    var length: comptime_int = 0;
            \\
            \\    for (std.meta.fields(Kind)) |entry| {
            \\        if(std.mem.indexOf(u8, entry.name, "metadata") == null) {
            \\            const value = get(@enumFromInt(entry.value));
            \\            if (@typeInfo(@TypeOf(value)) == .@"fn" and std.mem.indexOf(u8, entry.name, @tagName(kind)) != null) {
            \\                length += 1;
            \\            }
            \\        }
            \\    }
            \\
            \\    break :blk [length]template.Variant(module.key, T);
            \\} {
            \\    @setEvalBranchQuota((1 << 32) - 1);
            \\    const module = get(kind);
            \\
            \\    if (@typeInfo(@TypeOf(module)) == .@"fn") return &.{};
            \\
            \\    comptime var result: [std.meta.fields(Kind).len]template.Variant(module.key, T) = undefined;
            \\    var length: comptime_int = 0;
            \\
            \\    inline for (std.meta.fields(Kind)) |entry| {
            \\        if(comptime std.mem.indexOf(u8, entry.name, "metadata") == null) {
            \\            const value = get(@enumFromInt(entry.value));
            \\            if (@typeInfo(@TypeOf(value)) == .@"fn" and std.mem.indexOf(u8, entry.name, @tagName(kind)) != null) {
            \\                result[length] = value(T);
            \\                length += 1;
            \\            }
            \\        }
            \\    }
            \\
            \\    const slice = result[0..length];
            \\
            \\    comptime std.mem.sort(
            \\        template.Variant(module.key, T),
            \\        slice,
            \\        {},
            \\        struct {
            \\            fn sort(context: @TypeOf({}), lhs: template.Variant(module.key, T), rhs: template.Variant(module.key, T)) bool {
            \\                _ = context;
            \\                return lhs.score > rhs.score;
            \\            }
            \\        }.sort,
            \\    );
            \\
            \\    return slice.*;
            \\}
            \\
            ,
        },
    );

    // library
    const library = b.addLibrary(.{
        .linkage = .static,
        .name = "corundum",
        .root_module = root,
    });
    b.installArtifact(library);

    if (target.result.os.tag != .freestanding) {
        // executable
        const exe = b.addExecutable(.{
            .name = "corundum",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("corundum", root);
        b.installArtifact(exe);

        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_exe.addArgs(args);

        const run_step = b.step("run", "Run the executable");
        run_step.dependOn(&run_exe.step);
    }

    // wasm
    const wasm = b.addExecutable(.{
        .name = "corundum",
        .root_source_file = b.path("src/wasm.zig"),
        .target = b.resolveTargetQuery(.{
            .os_tag = .freestanding,
            .ofmt = .wasm,
            .cpu_arch = .wasm32,
        }),
        .optimize = optimize,
        .strip = optimize != .Debug,
        .error_tracing = optimize == .Debug,
    });

    wasm.entry = .disabled;
    wasm.export_memory = true;
    wasm.root_module.export_symbol_names = &.{
        "solve",
        "alloc",
        "free",
    };

    wasm.root_module.addImport("corundum", root);

    const wasm_install = b.addInstallArtifact(wasm, .{ .dest_dir = .{ .override = .{ .custom = "wasm" } } });

    const wasm_step = b.step("wasm", "Generate a WASM library");
    wasm_step.dependOn(&wasm_install.step);

    // docs
    const docs_step = b.step("docs", "Generate documentation");

    const install_docs = b.addInstallDirectory(.{
        .source_dir = library.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // perf
    const perf = b.addExecutable(.{
        .name = "perf",
        .root_source_file = b.path("src/perf.zig"),
        .target = target,
        .optimize = optimize,
    });
    perf.root_module.addImport("corundum", root);

    const perf_step = b.step("perf", "Generate performance metrics");
    perf_step.dependOn(wasm_step);

    const run_perf = b.addRunArtifact(perf);
    run_perf.step.dependOn(b.getInstallStep());
    perf_step.dependOn(&run_perf.step);
}

fn modules(b: *std.Build, root: *std.Build.Module, tests: *std.Build.Step.Run) !void {
    var iterator = (try std.fs.cwd().openDir("src", .{ .iterate = true })).iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.indexOf(u8, entry.name, ".zig") != entry.name.len - 4) continue;
        if (std.mem.eql(u8, "root.zig", entry.name)) continue;
        if (std.mem.eql(u8, "main.zig", entry.name)) continue;
        if (std.mem.eql(u8, "wasm.zig", entry.name)) continue;

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
        if (std.mem.indexOf(u8, entry.name, "._") == 0) continue;

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

        /// Code for the `.get` function.
        get_code: []const u8,

        /// Additional code.
        additional_code: []const u8,
    },
) !void {
    var generated = std.ArrayList(u8).init(b.allocator);

    try generated.appendSlice(b.fmt(
        \\// GENERATED FILE: DO NOT EDIT
        \\const std = @import("std");
        \\const {s} = @import("{s}");
        \\
        \\pub const {s} = struct {{
        \\    const Self = @This();
        \\
        \\    const inner: std.EnumMap(Kind, type) = .init(.{{
        \\
    , .{
        options.parent_name,
        options.parent_name,
        options.function_name,
    }));

    const File = struct {
        name: []const u8,
        basename: []const u8,
        entry_path: []const u8,
    };
    var files = std.ArrayList(File).init(b.allocator);
    defer files.deinit();

    var metadata = std.ArrayList(File).init(b.allocator);
    defer metadata.deinit();

    var walker = try (try std.fs.cwd().openDir(options.directory, .{ .iterate = true })).walk(b.allocator);
    defer walker.deinit();

    // collect all files
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig") and !std.mem.endsWith(u8, entry.path, ".zon")) continue;
        if (std.mem.indexOf(u8, entry.basename, "._") == 0) continue;

        const path = try std.mem.replaceOwned(u8, b.allocator, entry.path, "\\", "/");

        const info = File{
            .name = path[0 .. path.len - 4],
            .basename = entry.basename[0 .. entry.basename.len - 4],
            .entry_path = path,
        };
        try files.append(info);

        if (std.mem.endsWith(u8, entry.basename, ".zon")) {
            try metadata.append(info);
        }

        if (info.basename[0] != '_' and !std.mem.endsWith(u8, entry.basename, ".zon")) {
            try generated.appendSlice(b.fmt("        .@\"{s}\" = @import(\"{s}\"),\n", .{ info.name, info.name }));
        }
    }

    try generated.appendSlice(
        \\    });
        \\
    );

    try generated.appendSlice(options.get_code);
    try generated.appendSlice(options.additional_code);

    for (metadata.items) |info| {
        if (info.basename[0] != '_') {
            try generated.appendSlice(b.fmt("const @\"{s}\": Metadata = @import(\"{s}\");\n", .{ info.name, info.name }));
        }
    }

    try generated.appendSlice(
        \\
        \\};
        \\
        \\pub const Kind = enum {
        \\
    );

    for (files.items) |info| {
        if (info.basename[0] != '_') {
            try generated.appendSlice(b.fmt("    @\"{s}\",\n", .{info.name}));
        }
    }

    try generated.appendSlice("};\n");

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

        if (!std.mem.endsWith(u8, info.entry_path, ".zon")) {
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
