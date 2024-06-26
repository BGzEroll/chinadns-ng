const std = @import("std");
const root = @import("root");
const cc = @import("cc.zig");

const TestFn = struct {
    name: [:0]const u8,
    func: std.meta.FnPtr(fn () anyerror!void),
};

const all_test_fns = collect(.{root} ++ root.project_modules);

fn collect(comptime modules: anytype) [count(modules)]TestFn {
    @setEvalBranchQuota(1000000);
    var test_fns: [count(modules)]TestFn = undefined;
    var i = 0;
    for (modules) |module| {
        for (@typeInfo(module).Struct.decls) |decl| {
            if (std.mem.startsWith(u8, decl.name, "test:")) {
                test_fns[i] = .{
                    .name = decl.name ++ "",
                    .func = @field(module, decl.name),
                };
                i += 1;
            }
        }
    }
    return test_fns;
}

fn count(comptime modules: anytype) comptime_int {
    @setEvalBranchQuota(1000000);
    var n = 0;
    for (modules) |module| {
        for (@typeInfo(module).Struct.decls) |decl| {
            if (std.mem.startsWith(u8, decl.name, "test:"))
                n += 1;
        }
    }
    return n;
}

/// todo: support --test-filter [pattern]
/// todo: implement std.testing.allocator
pub fn main() u8 {
    if (all_test_fns.len <= 0)
        return 0;

    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var failed_count: usize = 0;

    for (all_test_fns) |test_fn| {
        cc.printf_err("%s\n", .{test_fn.name.ptr});

        if (nosuspend test_fn.func()) |_| {
            ok_count += 1;
            cc.printf_err("%-35s [\x1b[32;1mOK\x1b[0m]\n", .{test_fn.name.ptr});
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip_count += 1;
                cc.printf_err("%-35s [\x1b[34;1mSKIP\x1b[0m]\n", .{test_fn.name.ptr});
            },
            else => {
                failed_count += 1;
                cc.printf_err("\x1b[31;1merror: %s\x1b[0m\n", .{@errorName(err).ptr});
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpStackTrace(trace.*);
                cc.printf_err("%-35s [\x1b[31;1mFAILED\x1b[0m]\n", .{test_fn.name.ptr});
            },
        }

        cc.printf_err("\n", .{});
    }

    cc.printf_err("summary: %sOK: %zu\x1b[0m | %sSKIP: %zu\x1b[0m | %sFAILED: %zu\x1b[0m\n", .{
        @as([:0]const u8, if (ok_count > 0) "\x1b[32;1m" else "").ptr,
        ok_count,
        @as([:0]const u8, if (skip_count > 0) "\x1b[34;1m" else "").ptr,
        skip_count,
        @as([:0]const u8, if (failed_count > 0) "\x1b[31;1m" else "").ptr,
        failed_count,
    });

    return 0;
}
