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

    var iterator = (try std.fs.cwd().openDir("src", .{ .iterate = true })).iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.indexOf(u8, entry.name, ".zig") != entry.name.len - 4) continue;
        if (std.mem.eql(u8, "root.zig", entry.name)) continue;

        try submodules(b, root, entry, "src", run_unit_tests);
    }

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

fn submodules(b: *std.Build, root: *std.Build.Module, entry: std.fs.Dir.Entry, dir: []const u8, tests: *std.Build.Step.Run) !void {
    const name = entry.name[0 .. entry.name.len - 4];

    // module
    const module = b.addModule(name, .{
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
        const submodule = b.addModule(entry.name[0 .. entry.name.len - 4], .{
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
