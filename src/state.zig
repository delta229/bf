const std = @import("std");

const NUM_CELLS = 30000;

pub const State = struct {
    bp: usize,
    ip: usize,
    data: [NUM_CELLS]u8,
    program: []const u8,
};

pub const InterpretError = error{
    OutOfBounds,
    UnmatchedR,
    UnmatchedL,
    Halt,
};

pub fn Interpreter(
    comptime Err: type,
    comptime empty: []const u8,
    comptime step_fn: fn (state: *State, out: anytype, in: anytype) Err!void,
    comptime dump_fn: fn (state: *const State) void,
) type {
    return struct {
        const Self = @This();
        state: State,

        pub fn new() Self {
            var self: Self = undefined;
            self.reset();
            return self;
        }

        pub fn load(self: *Self, program: []const u8) void {
            self.state.program = program;
            self.state.ip = 0;
        }

        pub fn reset(self: *Self) void {
            self.load(empty);
            self.state.bp = 0;
            @memset(&self.state.data, 0);
        }

        pub fn run_for(
            self: *Self,
            count: ?usize,
            out: anytype,
            in: anytype,
            debug: bool,
        ) Err!void {
            var exec: usize = 0;
            while (self.state.ip < self.state.program.len and (count == null or exec < count.?))
                : (exec +|= 1)
            {
                if (debug) {
                    self.dump();
                }
                self.step(out, in) catch |err| {
                    if (err == InterpretError.Halt) {
                        break;
                    }

                    return err;
                };
            }
        }

        pub fn run_to_end(self: *Self, out: anytype, in: anytype, dbg: bool) !void {
            return self.run_for(null, out, in, dbg);
        }

        pub fn step(self: *Self, out: anytype, in: anytype) Err!void {
            return step_fn(&self.state, out, in);
        }

        pub fn dump(self: *const Self) void {
            return dump_fn(&self.state);
        }
    };
}
