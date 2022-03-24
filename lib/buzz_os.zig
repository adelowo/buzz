const std = @import("std");
const api = @import("./buzz_api.zig");
const utils = @import("../src/utils.zig");
const builtin = @import("builtin");

export fn time(vm: *api.VM) bool {
    vm.bz_pushNum(@intToFloat(f64, std.time.milliTimestamp()));

    return true;
}

export fn env(vm: *api.VM) bool {
    const key = api.Value.bz_valueToString(vm.bz_peek(0)) orelse "";

    if (std.os.getenvZ(key)) |value| {
        vm.bz_pushString(api.ObjString.bz_string(vm, utils.toCString(api.VM.allocator, value) orelse {
            vm.bz_throwString("Could not get environment variable");

            return false;
        }) orelse {
            vm.bz_throwString("Could not get environment variable");

            return false;
        });

        return true;
    }

    return false;
}

fn sysTempDir() []const u8 {
    return switch (builtin.os.tag) {
        .windows => unreachable, // TODO: GetTempPath
        else => std.os.getenv("TMPDIR") orelse std.os.getenv("TMP") orelse std.os.getenv("TEMP") orelse std.os.getenv("TEMPDIR") orelse "/tmp",
    };
}

export fn tmpDir(vm: *api.VM) bool {
    const tmp_dir: []const u8 = sysTempDir();

    vm.bz_pushString(api.ObjString.bz_string(vm, utils.toCString(api.VM.allocator, tmp_dir) orelse {
        vm.bz_throwString("Could not get tmp dir");

        return false;
    }) orelse {
        vm.bz_throwString("Could not get tmp dir");

        return false;
    });

    return true;
}

// TODO: what if file with same random name exists already?
export fn tmpFilename(vm: *api.VM) bool {
    const prefix: ?[*:0]const u8 = api.Value.bz_valueToString(vm.bz_peek(0));

    var random_part = std.ArrayList(u8).init(api.VM.allocator);
    defer random_part.deinit();
    random_part.writer().print("{x}", .{std.crypto.random.int(i64)}) catch {
        vm.bz_throwString("Could not get tmp file");

        return false;
    };

    var random_part_b64 = std.ArrayList(u8).initCapacity(api.VM.allocator, std.base64.standard.Encoder.calcSize(random_part.items.len)) catch {
        vm.bz_throwString("Could not get tmp file");

        return false;
    };
    random_part_b64.expandToCapacity();
    defer random_part_b64.deinit();

    _ = std.base64.standard.Encoder.encode(random_part_b64.items, random_part.items);

    var final = std.ArrayList(u8).init(api.VM.allocator);
    defer final.deinit();

    // TODO: take into account system file separator (windows is \)
    if (prefix) |uprefix| {
        final.writer().print("{s}{s}-{s}", .{ sysTempDir(), uprefix, random_part_b64.items }) catch {
            vm.bz_throwString("Could not get tmp file");

            return false;
        };
    } else {
        final.writer().print("{s}{s}", .{ sysTempDir(), random_part_b64.items }) catch {
            vm.bz_throwString("Could not get tmp file");

            return false;
        };
    }

    vm.bz_pushString(api.ObjString.bz_string(vm, utils.toCString(api.VM.allocator, final.items) orelse {
        vm.bz_throwString("Could not get tmp dir");

        return false;
    }) orelse {
        vm.bz_throwString("Could not get tmp dir");

        return false;
    });

    return true;
}

// If it was named `exit` it would be considered by zig as a callback when std.os.exit is called
export fn buzzExit(vm: *api.VM) bool {
    const exitCode: u8 = @floatToInt(u8, api.Value.bz_valueToNumber(vm.bz_peek(0)));

    std.os.exit(exitCode);

    return false;
}

export fn execute(vm: *api.VM) bool {
    const command: []const u8 = std.mem.sliceTo(api.Value.bz_valueToString(vm.bz_peek(1)) orelse "", 0);

    const child_process = std.ChildProcess.init(&[_][]const u8{command}, api.VM.allocator) catch {
        vm.bz_throwString("Could not execute");

        return false;
    };
    child_process.disable_aslr = true;

    child_process.spawn() catch {
        vm.bz_throwString("Could not execute");

        return false;
    };

    vm.bz_pushNum(@intToFloat(f64, (child_process.wait() catch |err| {
        std.debug.print("err: {}\n", .{err});
        vm.bz_throwString("Could not execute");

        return false;
    }).Exited));

    return true;
}
