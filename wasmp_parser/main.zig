const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{ EndOfStream, ReadError, PartiallyConsumed } || std.mem.Allocator.Error;
pub fn Parser(comptime Value: type, comptime Reader: type) type {
    return struct {
        const Self = @This();
        _parse: *const fn (self: *Self, allocator: Allocator, src: *Reader) anyerror!?Value,

        pub inline fn parse(self: *Self, allocator: Allocator, src: *Reader) anyerror!?Value {
            return self._parse(self, allocator, src);
        }
        pub fn voided(self: *Self) Parser(void, Reader) {
            return Voided(Value, Reader).init(self).parser;
        }
    };
}

pub fn Literal(comptime Reader: type) type {
    return struct {
        parser: Parser([]u8, Reader) = .{
            ._parse = &parse,
        },
        want: []const u8,

        const Self = @This();

        fn parse(parser: *Parser([]u8, Reader), allocator: Allocator, src: *Reader) anyerror!?[]u8 {
            const self = @fieldParentPtr(Self, "parser", parser);
            const buf = try allocator.alloc(u8, self.want.len);
            errdefer allocator.free(buf);
            const read = try src.reader().readAll(buf);
            if (read < self.want.len or !std.mem.eql(u8, buf, self.want)) {
                try src.seekableStream().seekBy(-@as(i64, @intCast(read)));

                allocator.free(buf);
                return null;
            }
            return buf;
        }

        pub fn init(want: []const u8) Self {
            return Self{ .want = want };
        }
    };
}

pub fn Voided(comptime Value: type, comptime Reader: type) type {
    return struct {
        parser: Parser(void, Reader) = .{
            ._parse = &parse,
        },
        child_parser: *Parser(Value, Reader),

        const Self = @This();

        fn parse(parser: *Parser(void, Reader), allocator: Allocator, src: *Reader) anyerror!?void {
            const self = @fieldParentPtr(Self, "parser", parser);
            const res = try self.child_parser.parse(allocator, src);
            if (res) |_| {
                return {};
            }
            return null;
        }
        pub fn init(child: *Parser(Value, Reader)) Self {
            return .{ .child_parser = child };
        }
    };
}
pub fn OneOf(comptime Value: type, comptime Reader: type) type {
    return struct {
        parser: Parser(Value, Reader) = .{
            ._parse = &parse,
        },
        parsers: []*Parser(Value, Reader),

        const Self = @This();

        pub fn init(parsers: []*Parser(Value, Reader)) Self {
            return Self{ .parsers = parsers };
        }

        fn parse(parser: *Parser(Value, Reader), allocator: Allocator, src: *Reader) anyerror!?Value {
            const self = @fieldParentPtr(Self, "parser", parser);
            for (self.parsers) |one_of_parser| {
                const res = try one_of_parser.parse(allocator, src);
                if (res != null)
                    return res;
            }
            return null;
        }
    };
}

pub fn Sequence(comptime Tuple: type, comptime Reader: type) type {
    const info = @typeInfo(Tuple).Struct;
    if (!info.is_tuple) @compileError("Tuple must be a... Tuple");
    comptime var new_fields: [info.fields.len]std.builtin.Type.StructField = undefined;
    for (info.fields, 0..) |field, i| {
        var new_field: std.builtin.Type.StructField = field;
        new_field.default_value = null;
        if (new_field.is_comptime)
            @compileError("no comptime fields");
        new_field.type = *Parser(field.type, Reader);
        new_fields[i] = new_field;
    }
    const ParserTuple = @Type(.{ .Struct = .{ .is_tuple = true, .fields = &new_fields, .decls = &.{}, .layout = .Auto } });
    return struct {
        parser: Parser(Tuple, Reader) = .{
            ._parse = &parse,
        },
        parsers: ParserTuple,

        const Self = @This();

        pub fn init(parsers: ParserTuple) Self {
            return .{ .parsers = parsers };
        }

        fn parse(parser: *Parser(Tuple, Reader), allocator: Allocator, src: *Reader) anyerror!?Tuple {
            const self = @fieldParentPtr(Self, "parser", parser);
            var res: Tuple = undefined;
            inline for (self.parsers, 0..) |p, i| {
                const parsed = try p.parse(allocator, src);
                if (parsed) |pp| {
                    res[i] = pp;
                } else {
                    return error.PartiallyConsumed;
                }
            }
            return res;
        }
    };
}

pub fn AnyChar(comptime Reader: type) type {
    return struct {
        parser: Parser(u8, Reader) = .{ ._parse = &parse },

        const Self = @This();

        pub fn init() Self {
            return .{};
        }
        fn parse(parser: *Parser(u8, Reader), allocator: Allocator, src: *Reader) anyerror!?u8 {
            _ = parser;
            _ = allocator;

            const res = try src.reader().readByte();
            return res;
        }
    };
}

pub fn ManyTill(comptime ManyVal: type, comptime TillVal: type, comptime Reader: type) type {
    return struct {
        parser: Parser([]ManyVal, Reader) = .{ ._parse = &parse },
        many_of: *Parser(ManyVal, Reader),
        til: *Parser(TillVal, Reader),

        const Self = @This();

        pub fn init(many: *Parser(ManyVal, Reader), til: *Parser(TillVal, Reader)) Self {
            return .{ .many_of = many, .til = til };
        }
        // u free the list nerd
        fn parse(parser: *Parser([]ManyVal, Reader), allocator: Allocator, src: *Reader) anyerror!?[]ManyVal {
            const self = @fieldParentPtr(Self, "parser", parser);
            var list = std.ArrayList(ManyVal).init(allocator);
            errdefer list.clearAndFree();
            while (true) {
                const tres = try self.til.parse(allocator, src);
                if (tres) |_| {
                    return list.items;
                }
                const many_res = try self.many_of.parse(allocator, src) orelse {
                    return error.PartiallyConsumed;
                };

                try list.append(many_res);
            }
        }
    };
}

pub fn strip_maps(alloc: Allocator, input: []const u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(input);
    const FbaType = @TypeOf(fbs);
    const ManyCharTillVoid = ManyTill(u8, []u8, FbaType);
    var anychar = AnyChar(FbaType).init();
    var map_lit = Literal(FbaType).init("-- <MAP>");
    var map_end_lit = Literal(FbaType).init("-- </MAP>");
    var map7_lit = Literal(FbaType).init("-- <MAP7>");
    var map7_end_lit = Literal(FbaType).init("-- </MAP7>");
    var many_til_map = ManyCharTillVoid.init(&anychar.parser, &map_lit.parser);
    var skip_map_end = ManyCharTillVoid.init(&anychar.parser, &map_end_lit.parser);
    var many_til_map7 = ManyCharTillVoid.init(&anychar.parser, &map7_lit.parser);
    var skip_map7_end = ManyCharTillVoid.init(&anychar.parser, &map7_end_lit.parser);

    var final = Sequence(struct { []u8, []u8, []u8, []u8 }, FbaType).init(.{ &many_til_map.parser, &skip_map_end.parser, &many_til_map7.parser, &skip_map7_end.parser });

    const res = (try final.parser.parse(alloc, &fbs)) orelse return error.BadParse;
    const rest = try fbs.reader().readAllAlloc(alloc, 65565);
    const out = try std.mem.join(alloc, "", &.{ res[0], res[2], rest });

    return out;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var args = try std.process.argsWithAllocator(alloc);
    if (!args.skip())
        return error.TooFewArgs;
    const inpath = args.next() orelse return error.TooFewArgs;
    const outpath = args.next() orelse return error.TooFewArgs;

    const infile = try std.fs.openFileAbsolute(inpath, .{});
    defer infile.close();
    const data = try infile.readToEndAlloc(alloc, 65565);

    //    std.debug.print("????\n", .{});
    const res = try strip_maps(alloc, data);
    //    std.debug.print("{s}", .{res});
    const outfile = try std.fs.createFileAbsolute(outpath, .{});
    defer outfile.close();

    try outfile.writeAll(res);
}
