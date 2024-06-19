const std = @import("std");

const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;
const InterpretError = error {
    OutOfBounds,
    NoMatchingFJump,
    NoMatchingRJump,
};

const NUM_CELLS = 30000;
pub const Interpreter = struct {
    bp: usize,
    ip: usize,
    data: [NUM_CELLS]u8,
    program: []const u8,

    pub fn new(program: []const u8) Interpreter {
        return .{ .bp = 0, .ip = 0, .program = program, .data = [_]u8{0} ** NUM_CELLS };
    }

    pub fn run_for(
        self: *Interpreter,
        count: ?usize,
        out: anytype,
        in: anytype,
        debug: bool,
    ) !void {
        var exec: usize = 0;
        while (self.ip < self.program.len and (count == null or exec < count.?)) : (exec +|= 1) {
            if (debug) {
                self.dump();
            }
            try self.step(out, in);
        }
    }

    pub fn run_to_end(self: *Interpreter, out: anytype, in: anytype, dbg: bool) !void {
        return self.run_for(null, out, in, dbg);
    }

    pub fn step(self: *Interpreter, out: anytype, in: anytype) !void {
        if (self.ip >= self.program.len) {
            return;
        }

        defer self.ip += 1;
        switch (self.program[self.ip]) {
            '>' => self.bp += 1,
            '<' => self.bp -= 1,
            '+' => self.data[self.bp] +%= 1,
            '-' => self.data[self.bp] -%= 1,
            '.' => try out.print("{c}", .{self.data[self.bp]}),
            ',' => self.data[self.bp] = try in.readByte(),
            '[' => {
                if (self.data[self.bp] != 0) {
                    return;
                }

                var count: usize = 0;
                while (self.ip < self.program.len) : (self.ip += 1) {
                    if (self.program[self.ip] == '[') {
                        count += 1;
                    } else if (self.program[self.ip] == ']') {
                        count -= 1;
                        if (count == 0) {
                            return;
                        }
                    }
                }
                return error.NoMatchingFJump;
            },
            ']' => {
                if (self.data[self.bp] == 0) {
                    return;
                }

                var count: usize = 0;
                while (true) {
                    if (self.program[self.ip] == ']') {
                        count += 1;
                    } else if (self.program[self.ip] == '[') {
                        count -= 1;
                        if (count == 0) {
                            return;
                        }
                    }

                    if (self.ip == 0) {
                        break;
                    }
                    self.ip -= 1;
                }

                return error.NoMatchingRJump;
            },
            else => {}, // BF ignores everything else
        }
    }

    pub fn reset(self: *Interpreter) void {
        self.bp = 0;
        self.ip = 0;
        @memset(&self.data, 0);
        self.program = ""[0..];
    }

    pub fn dump(self: *const Interpreter) void {
        if (self.ip < self.program.len) {
            std.debug.print("-> '{c}' | ", .{self.program[self.ip]});
        } else {
            std.debug.print("-> EOF | ", .{});
        }

        std.debug.print("IP: 0x{x:0>4} BP: 0x{x:0>4} [ ", .{self.ip, self.bp});
        const RANGE = 5;
        const min = self.bp -| RANGE;
        for (self.data[min..self.bp + 5], min..) |byte, i| {
            if (i == self.bp) {
                std.debug.print("\x1b[31;1;4m0x{x:0>2}\x1b[0m ", .{byte});
            } else {
                std.debug.print("0x{x:0>2} ", .{byte});
            }
        }
        std.debug.print("]\n", .{});
    }
};

fn expectOutput(program: []const u8, expected: []const u8) !void {
    var interpreter = Interpreter.new(program);

    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    const stdin = std.io.getStdIn().reader(); // TODO: some kind of "empty" reader
    try interpreter.run_to_end(&arr.writer(), &stdin, false);

    try std.testing.expectEqualStrings(expected, arr.items);
}

test "quine" {
    const program = @embedFile("./tests/392quine.bf");
    const expected = "->++>+++>+>+>+++>>>>>>>>>>>>>>>>>>>>+>+>++>+++>++>>+++>+>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>+>+>>+++>>+++>>>>>+++>+>>>>>>>>>++>+++>+++>+>>+++>>>+++>+>++>+++>>>+>+>++>+++>+>+>>+++>>>>>>>+>+>>>+>+>++>+++>+++>+>>+++>>>+++>+>++>+++>++>>+>+>++>+++>+>+>>+++>>>>>+++>+>>>>>++>+++>+++>+>>+++>>>+++>+>+++>+>>+++>>+++>>++[[>>+[>]++>++[<]<-]>+[>]<+<+++[<]<+]>+[>]++++>++[[<++++++++++++++++>-]<+++++++++.<]\x1a";
    try expectOutput(program, expected);
}

test "hw" {
    const program = @embedFile("./tests/hw.bf");
    try expectOutput(program, "Hello World!\n");
}

test "hw_comments" {
    const program = @embedFile("./tests/hw_comments.bf");
    try expectOutput(program, "Hello World!\n");
}

test "squares" {
    const program = @embedFile("./tests/squares.bf");
    const expected = "0\n1\n4\n9\n16\n25\n36\n49\n64\n81\n100\n121\n144\n169\n196\n225\n256\n289\n324\n361\n400\n441\n484\n529\n576\n625\n676\n729\n784\n841\n900\n961\n1024\n1089\n1156\n1225\n1296\n1369\n1444\n1521\n1600\n1681\n1764\n1849\n1936\n2025\n2116\n2209\n2304\n2401\n2500\n2601\n2704\n2809\n2916\n3025\n3136\n3249\n3364\n3481\n3600\n3721\n3844\n3969\n4096\n4225\n4356\n4489\n4624\n4761\n4900\n5041\n5184\n5329\n5476\n5625\n5776\n5929\n6084\n6241\n6400\n6561\n6724\n6889\n7056\n7225\n7396\n7569\n7744\n7921\n8100\n8281\n8464\n8649\n8836\n9025\n9216\n9409\n9604\n9801\n10000\n";
    try expectOutput(program, expected);
}
