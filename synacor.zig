const std = @import("std");

fn arg(memory: var, registers: var, index: usize) u16 {
    const value = memory[index];

    if (value < 32768) {
        return value;
    } else {
        return registers[value - 32768];
    }
}

fn mod(value: u16) u16 {
    return value % 32768;
}

const Stack = struct {
    head: usize = 0,
    values: [65536]u16 = undefined,

    pub fn push(self: *Stack, value: u16) void {
        self.head += 1;
        self.values[self.head] = value;
    }

    pub fn peek(self: Stack) u16 {
        return self.values[self.head];
    }

    pub fn pop(self: *Stack) u16 {
        const value = self.peek();

        self.values[self.head] = undefined;
        self.head -= 1;

        return value;
    }
};

pub fn main() !void {
    // 15-bit address space for memory.
    var raw: [65536]u8 = undefined;
    var memory: [32768]u16 = undefined;
    var registers = [_]u16{0} ** 8;
    var stack = Stack{};

    const stdout = std.io.getStdOut().outStream();
    const stdin = std.io.getStdIn().inStream();
    const file = try std.fs.cwd().openFile("challenge.bin", .{});
    defer file.close();
    const file_size = try file.getEndPos();
    _ = try file.read(raw[0..file_size]);

    var i: usize = 0;

    while (i <= file_size) : (i += 2) {
        memory[i / 2] = (@intCast(u16, raw[i + 1]) << 8) | (raw[i] & 0xff);
    }

    i = 0;

    var opcode: u16 = 0;
    var a_: u16 = 0;
    var a: u16 = 0;
    var b_: u16 = 0;
    var b: u16 = 0;
    var c_: u16 = 0;
    var c: u16 = 0;

    while (true) {
        opcode = memory[i];
        a = arg(memory, registers, i + 1);
        b = arg(memory, registers, i + 2);
        c = arg(memory, registers, i + 3);

        if (memory[i + 1] >= 32768) {
            a_ = memory[i + 1] - 32768;
        }

        switch (opcode) {
            // halt
            0 => break,
            // set
            1 => blk: {
                registers[a_] = b;
                i += 3;
            },
            // push
            2 => blk: {
                stack.push(a);
                i += 2;
            },
            // pop
            3 => blk: {
                registers[a_] = stack.pop();
                i += 2;
            },
            // eq
            4 => blk: {
                registers[a_] = @boolToInt(b == c);
                i += 4;
            },
            // gt
            5 => blk: {
                registers[a_] = @boolToInt(b > c);
                i += 4;
            },
            // jmp
            6 => i = a,
            // jt
            7 => blk: {
                if (a != 0) {
                    i = b;
                } else {
                    i += 3;
                }
            },
            // jf
            8 => blk: {
                if (a == 0) {
                    i = b;
                } else {
                    i += 3;
                }
            },
            // add
            9 => blk: {
                registers[a_] = mod(b + c);
                i += 4;
            },
            // mult
            10 => blk: {
                registers[a_] = @intCast(u16, (@intCast(u32, b) * @intCast(u32, c)) % 32768);
                i += 4;
            },
            // mod
            11 => blk: {
                registers[a_] = mod(b % c);
                i += 4;
            },
            // and
            12 => blk: {
                registers[a_] = b & c;
                i += 4;
            },
            // or
            13 => blk: {
                registers[a_] = b | c;
                i += 4;
            },
            // not
            14 => blk: {
                registers[a_] = mod(~b);
                i += 3;
            },
            // rmem
            15 => blk: {
                registers[a_] = memory[b];
                i += 3;
            },
            // wmem
            16 => blk: {
                memory[a] = b;
                i += 3;
            },
            // call
            17 => blk: {
                stack.push(@intCast(u16, i + 2));
                i = a;
            },
            // ret
            18 => blk: {
                i = stack.pop();
            },
            // out
            19 => blk: {
                _ = try std.fmt.formatAsciiChar(@intCast(u8, a), .{}, stdout);
                i += 2;
            },
            // in
            20 => blk: {
                registers[a_] = try stdin.readByte();
                i += 2;
            },
            // noop
            21 => i += 1,
            else => blk: {
                try stdout.print("unhandled opcode: {}\n", .{opcode});
                break;
            },
        }
    }
}
