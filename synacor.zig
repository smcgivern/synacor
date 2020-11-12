const std = @import("std");

fn arg(memory: anytype, registers: anytype, index: usize) u16 {
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

    const source = try std.fs.cwd().openFile("challenge.bin", .{});
    defer source.close();

    var history_file: [21]u8 = undefined;
    _ = try std.fmt.bufPrint(history_file[0..], "{}.{}", .{ "history", std.time.milliTimestamp() });
    const history = try std.fs.cwd().createFile(&history_file, .{});
    defer history.close();

    const source_size = try source.getEndPos();
    _ = try source.read(raw[0..source_size]);

    var i: usize = 0;

    while (i <= source_size) : (i += 2) {
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
            1 => {
                registers[a_] = b;
                i += 3;
            },
            // push
            2 => {
                stack.push(a);
                i += 2;
            },
            // pop
            3 => {
                registers[a_] = stack.pop();
                i += 2;
            },
            // eq
            4 => {
                registers[a_] = @boolToInt(b == c);
                i += 4;
            },
            // gt
            5 => {
                registers[a_] = @boolToInt(b > c);
                i += 4;
            },
            // jmp
            6 => i = a,
            // jt
            7 => {
                if (a != 0) {
                    i = b;
                } else {
                    i += 3;
                }
            },
            // jf
            8 => {
                if (a == 0) {
                    i = b;
                } else {
                    i += 3;
                }
            },
            // add
            9 => {
                registers[a_] = mod(b + c);
                i += 4;
            },
            // mult
            10 => {
                registers[a_] = @intCast(u16, (@intCast(u32, b) * @intCast(u32, c)) % 32768);
                i += 4;
            },
            // mod
            11 => {
                registers[a_] = mod(b % c);
                i += 4;
            },
            // and
            12 => {
                registers[a_] = b & c;
                i += 4;
            },
            // or
            13 => {
                registers[a_] = b | c;
                i += 4;
            },
            // not
            14 => {
                registers[a_] = mod(~b);
                i += 3;
            },
            // rmem
            15 => {
                registers[a_] = memory[b];
                i += 3;
            },
            // wmem
            16 => {
                memory[a] = b;
                i += 3;
            },
            // call
            17 => {
                stack.push(@intCast(u16, i + 2));
                i = a;
            },
            // ret
            18 => {
                i = stack.pop();
            },
            // out
            19 => {
                _ = try std.fmt.formatAsciiChar(@intCast(u8, a), .{}, stdout);
                i += 2;
            },
            // in
            20 => {
                var input = try stdin.readByte();
                registers[a_] = input;
                i += 2;

                _ = try history.write(&[1]u8{input});
            },
            // noop
            21 => i += 1,
            else => {
                try stdout.print("unhandled opcode: {}\n", .{opcode});
                break;
            },
        }
    }
}
