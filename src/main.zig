const std = @import("std");
const clap = @import("clap");
const bc = @import("./bc.zig");
const Allocator = std.mem.Allocator;

fn repl(alloc: Allocator, out: *const std.fs.File.Writer, in: *const std.fs.File.Reader) !void {
    var code = try bc.compile("", alloc);
    defer code.deinit();

    var buffer: [2048]u8 = undefined;
    var vm = bc.Interpreter.new();
    var debug = false;
    var id = false;
    while (true) {
        std.debug.print(">> ", .{});

        const Command = enum { quit, reset, dump, debug, id };
        const command = in.readUntilDelimiter(&buffer, '\n') catch |err| {
            if (err == error.EndOfStream) {
                return;
            }

            std.debug.print("Error reading input: '{}'\n", .{err});
            continue;
        };

        const cmd = std.meta.stringToEnum(Command, command) orelse {
            code.deinit();
            code = try bc.compile(command, alloc);

            vm.load(code.items);
            vm.run_to_end(out, in, debug and id) catch |err| {
                std.debug.print("\nError: '{}'\n", .{err});
            };
            if (debug and !id) {
                vm.dump();
            }
            continue;
        };
        switch (cmd) {
            .quit => break,
            .reset => vm.reset(),
            .dump => vm.dump(),
            .debug => {
                debug = !debug;
                std.debug.print("Debug mode is {s}\n", .{if (debug) "enabled" else "disabled"});
            },
            .id => {
                id = !id;
                std.debug.print("Instruction dump mode is {s}\n", .{if (debug) "enabled" else "disabled"});
            },
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-d, --debug            Enable instruction debug mode.
        \\-p, --print            Dump bytecode instead of executing.
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = alloc,
    }) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    if (res.args.help != 0) {
        return clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
    } else if (res.positionals.len > 0) {
        const MAX_PROGRAM = 0xffff_ffff;
        const data = if (std.mem.eql(u8, res.positionals[0], "-")) out: {
            break :out try stdin.readAllAlloc(alloc, MAX_PROGRAM);
        } else out: {
            const fp = try std.fs.cwd().openFile(res.positionals[0], .{});
            defer fp.close();

            break :out try fp.readToEndAlloc(alloc, MAX_PROGRAM);
        };
        defer alloc.free(data);

        const code = try bc.compile(data, alloc);
        defer code.deinit();

        if (res.args.print != 0) {
            bc.dump_all(code.items);
            std.debug.print("\n\n", .{});
        } else {
            var vm = bc.Interpreter.new();
            vm.load(code.items[0..]);
            return vm.run_to_end(&stdout, &stdin, res.args.debug != 0);
        }
    } else {
        return repl(alloc, &stdout, &stdin);
    }
}
