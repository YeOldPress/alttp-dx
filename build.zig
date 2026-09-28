const std = @import("std");

var sdl_include: ?[]const u8 = null;
var sdl_lib: ?[]const u8 = null;

// C sources that have not been ported to Zig yet. As modules are translated,
// they move out of this list and are referenced from zelda_zig.zig instead.
const c_sources = [_][]const u8{
    "third_party/gl_core/gl_core_3_1.c",
    // Carries the stb_image implementation used by glsl_shader.zig.
    "third_party/stb/stb_image_impl.c",
    "third_party/opus-1.3.1-stripped/opus_decoder_amalgam.c",
};

const c_flags = [_][]const u8{
    "-std=gnu11",
    // The upstream C build used plain clang with no sanitizers. The remaining
    // third-party C reads unaligned uint16s on purpose, which zig's default
    // UBSan traps on; the Zig code uses *align(1) pointers instead, so these
    // flags now only cover third_party/.
    "-fno-sanitize=undefined",
    "-Wno-unused-but-set-variable",
    "-Wno-incompatible-pointer-types",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Windows has no pkg-config by custom, so the SDL3 location can be given
    // directly. Either may be used on its own; whatever is not given falls
    // back to pkg-config and then to a bare -lSDL3.
    sdl_include = b.option(
        []const u8,
        "sdl-include",
        "Directory holding SDL3/SDL.h, for platforms without pkg-config",
    );
    sdl_lib = b.option(
        []const u8,
        "sdl-lib",
        "Directory holding the SDL3 import library or shared library",
    );
    const optimize = b.standardOptimizeOption(.{});

    // The SNES emulation is its own module so that nothing under src/ has to
    // reach across the directory with a relative path. The dependency only
    // goes one way: snes/ never imports the game.
    const snes_mod = b.createModule(.{
        .root_source_file = b.path("snes/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "zelda3",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addIncludePath(b.path("."));
    exe.root_module.addCSourceFiles(.{
        .files = &c_sources,
        .flags = &c_flags,
    });

    // The shipped zelda3.ini, built into the game so a folder or data
    // directory without one still starts. @embedFile only reaches files
    // inside a module's own directory, so the ini goes into a generated
    // module next to a one-line wrapper.
    const default_ini_files = b.addWriteFiles();
    _ = default_ini_files.addCopyFile(b.path("zelda3.ini"), "zelda3.ini");
    const default_ini = b.createModule(.{
        .root_source_file = default_ini_files.add("default_ini.zig", "pub const text = @embedFile(\"zelda3.ini\");\n"),
    });

    // The ported modules compile to one object that is linked in alongside the
    // remaining C. Each one exports the same symbols its C file used to.
    const zig_obj = b.addObject(.{
        .name = "zelda_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zelda_zig.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    zig_obj.root_module.addIncludePath(b.path("."));
    zig_obj.root_module.addImport("snes", snes_mod);
    zig_obj.root_module.addImport("default_ini", default_ini);
    exe.root_module.addObject(zig_obj);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zelda_zig.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    tests.root_module.addIncludePath(b.path("."));
    tests.root_module.addImport("snes", snes_mod);
    tests.root_module.addImport("default_ini", default_ini);
    // Exercise the same C/Zig boundaries as the game while the port is in
    // progress. Real implementations replace the former panic-only stubs.
    tests.root_module.addCSourceFiles(.{
        .files = &c_sources,
        .flags = &c_flags,
    });
    const reference = b.option([]const u8, "ancilla-reference", "Original C oracle, as other/check_ancilla_parity.zig generates it");
    const test_options = b.addOptions();
    test_options.addOption(bool, "ancilla_parity", reference != null);
    tests.root_module.addOptions("build_options", test_options);
    if (reference) |path| {
        // The oracle carries its own headers from the baseline commit, so it
        // needs no include path into the (now header-free) source tree.
        tests.root_module.addCSourceFile(.{ .file = .{ .cwd_relative = path }, .flags = &c_flags });
    }
    const test_step = b.step("test", "Run tests for the ported Zig modules");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // Tests in a dependency module are not discovered through the module that
    // imports it, so the emulation gets its own run.
    const snes_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("snes/test_root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(snes_tests).step);

    // The start menu's tests read the real zelda3.ini and need no game, so
    // they get a run of their own rooted at the menu.
    const menu_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/menu.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    menu_tests.root_module.addIncludePath(b.path("."));
    menu_tests.root_module.addImport("default_ini", default_ini);
    addSdlIncludes(b, menu_tests.root_module);
    linkSdlLibs(b, menu_tests.root_module);
    test_step.dependOn(&b.addRunArtifact(menu_tests).step);

    // The asset tooling needs no SDL; it is plain byte wrangling. Rooting the
    // test at asset_all.zig pulls in every asset module with it.
    const asset_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/asset_all.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(asset_tests).step);

    // Every module that sees SDL headers or symbols, C and Zig alike.
    for ([_]*std.Build.Module{ exe.root_module, zig_obj.root_module, tests.root_module }) |m| {
        addSdlIncludes(b, m);
    }
    linkSdlLibs(b, exe.root_module);
    linkSdlLibs(b, tests.root_module);
    exe.root_module.linkSystemLibrary("m", .{});
    tests.root_module.linkSystemLibrary("m", .{});

    if (target.result.os.tag == .macos) {
        // Zig only looks in the macOS SDK for a native target. Naming a
        // minimum version, as the release build does, stops it being native,
        // so the frameworks have to be pointed at by hand.
        if (!target.query.isNativeOs() and b.graph.host.result.os.tag == .macos) {
            if (std.zig.system.darwin.getSdk(b.allocator, b.graph.io, &target.result)) |sdk| {
                exe.root_module.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System/Library/Frameworks" }) });
            }
        }
        exe.root_module.linkFramework("OpenGL", .{});
        // Room for the release packaging to repoint SDL3 at the copy inside
        // the app bundle, which is a longer path than the one linked against.
        exe.headerpad_max_install_names = true;
    }

    // The triforce icon, so the Windows binary is not a blank default one.
    if (target.result.os.tag == .windows) {
        exe.root_module.addWin32ResourceFile(.{ .file = b.path("src/platform/win32/zelda3.rc") });
    }

    b.installArtifact(exe);

    // zelda3-tools: the asset tools, with a window and a command line. It
    // needs the asset builder and SDL, not the game.
    const tools = b.addExecutable(.{
        .name = "zelda3-tools",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    tools.root_module.addIncludePath(b.path("."));
    addSdlIncludes(b, tools.root_module);
    linkSdlLibs(b, tools.root_module);
    tools.headerpad_max_install_names = target.result.os.tag == .macos;
    b.installArtifact(tools);

    const tools_run = b.addRunArtifact(tools);
    tools_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| tools_run.addArgs(args);
    b.step("tools", "Build and run zelda3-tools").dependOn(&tools_run.step);

    const tools_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    tools_tests.root_module.addIncludePath(b.path("."));
    addSdlIncludes(b, tools_tests.root_module);
    linkSdlLibs(b, tools_tests.root_module);
    test_step.dependOn(&b.addRunArtifact(tools_tests).step);

    // Making zelda3_assets.dat without opening a window, for a first build or
    // for CI. The start menu does this itself when the assets are missing.
    const assets_run = b.addRunArtifact(exe);
    assets_run.step.dependOn(b.getInstallStep());
    assets_run.addArg("--build-assets");
    const assets_step = b.step("assets", "Build zelda3_assets.dat from zelda3.sfc");
    assets_step.dependOn(&assets_run.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Build and run zelda3");
    run_step.dependOn(&run_cmd.step);
}

// SDL3 is a system dependency. It ships no sdl3-config, so the paths come from
// pkg-config, which also covers Homebrew installing outside the default search
// path. -Dsdl-include and -Dsdl-lib override that for platforms where
// pkg-config is not how anyone finds a library, which in practice means
// Windows.
fn addSdlIncludes(b: *std.Build, m: *std.Build.Module) void {
    if (sdl_include) |dir| {
        m.addIncludePath(.{ .cwd_relative = dir });
        return;
    }
    const cflags = sdl3PkgConfig(b, "--cflags") orelse return;
    var it = std.mem.tokenizeAny(u8, cflags, " \r\n");
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-I")) {
            m.addIncludePath(.{ .cwd_relative = arg[2..] });
        } else if (std.mem.startsWith(u8, arg, "-D")) {
            const body = arg[2..];
            if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
                m.addCMacro(body[0..eq], body[eq + 1 ..]);
            } else {
                m.addCMacro(body, "1");
            }
        }
    }
}

fn linkSdlLibs(b: *std.Build, m: *std.Build.Module) void {
    if (sdl_lib) |dir| {
        m.addLibraryPath(.{ .cwd_relative = dir });
        m.linkSystemLibrary("SDL3", .{});
        return;
    }
    const libs = sdl3PkgConfig(b, "--libs") orelse {
        m.linkSystemLibrary("SDL3", .{});
        return;
    };
    var it = std.mem.tokenizeAny(u8, libs, " \r\n");
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-L")) {
            m.addLibraryPath(.{ .cwd_relative = arg[2..] });
        } else if (std.mem.startsWith(u8, arg, "-l")) {
            m.linkSystemLibrary(arg[2..], .{});
        }
    }
}

/// Null when pkg-config is missing or knows nothing about sdl3, so the caller
/// can fall back to a plain -lSDL3 and let the linker look in the usual places.
fn sdl3PkgConfig(b: *std.Build, arg: []const u8) ?[]const u8 {
    const exe_path = b.findProgram(&.{"pkg-config"}, &.{}) catch return null;
    // A nonzero exit (no sdl3.pc installed) comes back as an error, not a code.
    var code: u8 = undefined;
    return b.runAllowFail(&.{ exe_path, arg, "sdl3" }, &code, .ignore) catch null;
}
