const std = @import("std");
const ArrayList = std.ArrayList;

const Opcode = enum(u8) {
    halt = 0,
    inc,
    dec,
    left,
    right,
    out,
    in,
    jz, // u32 operand
    jnz, // u32 operand
};

pub fn compile(program: []const u8, alloc: std.mem.Allocator) !ArrayList(u8) {
    var bc = ArrayList(u8).init(alloc);
    var jumps = ArrayList(u32).init(alloc);
    defer jumps.deinit();

    for (program) |char| {
        switch (char) {
            '>' => try bc.append(@intFromEnum(Opcode.right)),
            '<' => try bc.append(@intFromEnum(Opcode.left)),
            '+' => try bc.append(@intFromEnum(Opcode.inc)),
            '-' => try bc.append(@intFromEnum(Opcode.dec)),
            '.' => try bc.append(@intFromEnum(Opcode.out)),
            ',' => try bc.append(@intFromEnum(Opcode.in)),
            '[' => {
                try bc.append(@intFromEnum(Opcode.jz));
                try jumps.append(@intCast(bc.items.len)); // TODO: report error if jump dist is too great
                try bc.appendNTimes(0, 4);
            },
            ']' => {
                const last = jumps.popOrNull() orelse {
                    return error.UnmatchedR;
                };

                var buffer: [4]u8 = undefined;
                std.mem.writeInt(u32, &buffer, @intCast(last + 4), .little);

                try bc.append(@intFromEnum(Opcode.jnz));
                try bc.appendSlice(&buffer);

                std.mem.writeInt(u32, &buffer, @intCast(bc.items.len), .little);
                std.mem.copyForwards(u8, bc.items[last..], &buffer);
            },
            else => {}, // BF ignores everything else
        }
    }

    if (jumps.items.len > 0) {
        return error.UnmatchedL;
    }

    try bc.append(@intFromEnum(Opcode.halt));
    return bc;
}

pub fn dump_all(bc: []const u8) void {
    var ip: usize = 0;
    while (ip < bc.len) {
        dump_one(bc, &ip);
        std.debug.print("\n", .{});
    }
}

pub fn dump_one(bc: []const u8, ip: *usize) void {
    std.debug.print("0x{x:0>4}  ", .{ip.*});
    if (ip.* >= bc.len) {
        return std.debug.print("EOF       ", .{});
    }

    const byte = bc[ip.*];
    ip.* += 1;
    const instr = std.meta.intToEnum(Opcode, byte) catch {
        std.debug.print("UNK {x:0>2}", .{byte});
        return;
    };

    // FIXME: spaces extremely lazy
    switch (instr) {
        .inc => std.debug.print("INC       ", .{}),
        .dec => std.debug.print("DEC       ", .{}),
        .left => std.debug.print("L       ", .{}),
        .right => std.debug.print("R       ", .{}),
        .out => std.debug.print("OUT       ", .{}),
        .in => std.debug.print("IN       ", .{}),
        .jz => {
            std.debug.print("JZ   {x:0>4}", .{std.mem.readInt(u32, bc[ip.*..][0..4], .little)});
            ip.* += 4;
        },
        .jnz => {
            std.debug.print("JNZ  {x:0>4}", .{std.mem.readInt(u32, bc[ip.*..][0..4], .little)});
            ip.* += 4;
        },
        .halt => std.debug.print("HLT       ", .{}),
    }
}

const NUM_CELLS = 65535;
const EMPTY_PROGRAM = [_]u8{@intFromEnum(Opcode.halt)};

pub const InterpretError = error{
    OutOfBounds,
    Halt,
    CorruptedBytecode,
};

pub const Interpreter = struct {
    const Self = @This();

    bp: usize,
    ip: usize,
    data: [NUM_CELLS]u8,
    program: []const u8,

    pub fn new() Self {
        var self: Self = undefined;
        self.reset();
        return self;
    }

    pub fn load(self: *Self, program: []const u8) void {
        self.program = program;
        self.ip = 0;
    }

    pub fn reset(self: *Self) void {
        self.load(&EMPTY_PROGRAM);
        self.bp = 0;
        @memset(&self.data, 0);
    }

    pub fn run_for(self: *Self, count: ?usize, out: anytype, in: anytype, dbg: bool) !void {
        var exec: usize = 0;
        while (self.ip < self.program.len and (count == null or exec < count.?)) : (exec +|= 1) {
            if (dbg) {
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

    pub fn step(self: *Self, out: anytype, in: anytype) !void {
        if (self.ip >= self.program.len) {
            return;
        }

        const opcode = std.meta.intToEnum(Opcode, self.program[self.ip]) catch {
            return InterpretError.CorruptedBytecode;
        };

        self.ip += 1;
        switch (opcode) {
            .right => self.bp += 1,
            .left => self.bp -= 1,
            .inc => self.data[self.bp] +%= 1,
            .dec => self.data[self.bp] -%= 1,
            .out => try out.print("{c}", .{self.data[self.bp]}),
            .in => self.data[self.bp] = in.readByte() catch 0, // EOF = 0, other options are -1 or do nothing
            .jz => {
                if (self.data[self.bp] == 0) {
                    self.ip = std.mem.readInt(u32, self.program[self.ip..][0..4], .little);
                } else {
                    self.ip += 4;
                }
            },
            .jnz => {
                if (self.data[self.bp] != 0) {
                    self.ip = std.mem.readInt(u32, self.program[self.ip..][0..4], .little);
                } else {
                    self.ip += 4;
                }
            },
            .halt => return InterpretError.Halt,
        }
    }

    pub fn dump(self: *const Self) void {
        var ip = self.ip;
        dump_one(self.program, &ip);
        std.debug.print("\t\t | BP: 0x{x:0>4} [ ", .{self.bp});

        const RANGE = 5;
        const min = self.bp -| RANGE;
        for (self.data[min .. self.bp + RANGE + 1], min..) |byte, i| {
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
    const buf = try compile(program, std.testing.allocator);
    defer buf.deinit();

    var vm = Interpreter.new();
    vm.load(buf.items);

    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    const stdin = std.io.getStdIn().reader(); // TODO: some kind of "empty" reader
    try vm.run_to_end(&arr.writer(), &stdin, false);

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

test "output_h" {
    const program = @embedFile("./tests/output_h.bf");
    try expectOutput(program, "H\n");
}
