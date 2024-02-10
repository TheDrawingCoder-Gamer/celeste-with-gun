const Audio = @This();

const std = @import("std");
const tic = @import("tic80.zig");

pub const Waveform = [16]u8;
pub const FreqVolume = packed struct(u16) {
    frequency: u12,
    volume: u4,
};
// why
pub const SoundRegister = extern struct { fv: FreqVolume, waveform: Waveform };
pub const Volume = packed struct { left: u4 = 0, right: u4 = 0 };

pub const channels: *[4]SoundRegister = @alignCast(@ptrCast(tic.SOUND_REGISTERS));
// TODO: make sure this pointer is REAL!
pub const waveforms: *[16]Waveform = @ptrCast(tic.WAVEFORMS);
pub const stereo_volume: *[4]Volume = @ptrCast(tic.STEREO_VOLUME);

pub const SfxSample = extern struct {
    pub const Item = packed struct(u16) {
        volume: u4 = 0,
        wave: u4 = 0,
        chord: u4 = 0,
        pitch: i4 = 0,
    };
    pub const Loop = packed struct(u8) {
        start: u4 = 0,
        size: u4 = 0,
        pub fn calc_loop(self: *const @This(), pos: u32) u32 {
            var offset: u32 = 0;
            if (self.size > 0) {
                for (0..@as(usize, pos)) |_| {
                    if (offset < (self.start + self.size - 1)) {
                        offset += 1;
                    } else {
                        offset = self.start;
                    }
                }
            } else {
                offset = if (pos >= SFX_TICKS) SFX_TICKS - 1 else pos;
            }

            return offset;
        }
    };
    pub const Info = packed struct(u16) { octave: u3, pitch16x: bool, speed: i3, reverse: bool, note: u4, stereo_left: bool, stereo_right: bool, temp: u2 };
    pub const Loops = extern union { loops: [4]Loop, loop: extern struct { wave: Loop, volume: Loop, chord: Loop, pitch: Loop } };
    sequence: [30]Item,
    info: Info,
    loops: Loops,
};

pub const sfx_samples: *[64]SfxSample = @alignCast(@ptrCast(tic.SFX));
pub const MusicCommand = enum(u3) { empty, volume, chord, jump, slide, pitch, vibrato, delay };
pub const TrackRow = packed struct(u24) {
    note: u4,
    param1: u4,
    param2: u4,
    command: MusicCommand,
    sfx_hi: u1,
    sfx_lo: u5,
    octave: u3,
    pub fn param2val(self: @This()) u8 {
        return (@as(u8, self.param1) << 4) + self.param2;
    }
    pub fn sfx(self: @This()) u6 {
        return (@as(u6, self.sfx_hi) << 5) + self.sfx_lo;
    }
};
// TODO: Param on slide jank and tied to ticks
pub const MusicPattern = extern struct {
    const Self = @This();
    const MusicPatternIO = std.packed_int_array.PackedIntIo(TrackRow, .little);
    bytes: [MUSIC_PATTERN_ROWS * 3]u8,

    pub fn get(self: Self, index: usize) TrackRow {
        return MusicPatternIO.get(&self.bytes, index, 0);
    }
};

comptime {
    if (@sizeOf(SoundRegister) != 18) {
        @compileError("sound register doesn't match ram repr");
    }
    if (@sizeOf(MusicPattern) != 192) {
        @compileError("music pattern doesn't match RAM repr");
    }
}

pub const music_patterns: *[60]MusicPattern = @ptrCast(tic.MUSIC_PATTERNS);

const TIC_FRAMERATE = 60;
const NOTES_PER_BEAT = 4;
const SECONDS_PER_MINUTE = 60;
const DEFAULT_SPEED = 6;
const NOTES_PER_MINUTE = TIC_FRAMERATE / NOTES_PER_BEAT * SECONDS_PER_MINUTE;
const MUSIC_PATTERN_ROWS = 64;
const NOTE_STOP = 1;
const NOTE_START = 4;
const NOTES = 12;
const OCTAVES = 8;
const MAX_VOLUME = 15;
const PITCH_DELTA = 128;
const PIANO_START = 8;
const SFX_TICKS = 30;

pub const CommandData = struct {
    pub const Chord = struct {
        tick: u32 = 0,
        note1: u4 = 0,
        note2: u4 = 0,
    };
    pub const Vibrato = struct {
        tick: u32 = 0,
        period: u4 = 0,
        depth: u4 = 0,
    };
    pub const Slide = struct {
        tick: u32 = 0,
        note: u32 = 0,
        duration: u32 = 0,
    };
    pub const Finepitch = packed struct { value: i32 = 0 };

    pub const Delay = struct { row: ?TrackRow = null, ticks: u32 = 0 };
    chord: Chord = .{},
    vibrato: Vibrato = .{},
    slide: Slide = .{},
    finepitch: Finepitch = .{},
    delay: Delay = .{},
};
pub const ChannelData = struct {
    const Self = @This();
    tick: u32 = 0,
    sfx_index: ?u32 = 0,
    note: u32 = 0,
    volume: Volume = .{},
    speed: i3 = 0,
    duration: ?u32 = null,
    sfx_pos: SfxPos = .{},

    pub fn set_from_data(self: *Self, index: ?u32, note: u4, octave: u3, duration: ?u32, vol_left: u4, vol_right: u4, speed: ?i3) void {
        self.volume.left = vol_left;
        self.volume.right = vol_right;

        if (index) |idx| {
            self.speed = speed orelse sfx_samples[idx].info.speed;
        }

        self.note = @as(u32, note) + @as(u32, octave) * NOTES;
        self.duration = duration;
        self.sfx_index = index;

        self.sfx_pos = .{};
    }

    pub fn set_music_data(self: *Self, index: ?u32, note: u4, octave: u3, vol_left: u4, vol_right: u4) void {
        self.set_from_data(index, note, octave, null, vol_left, vol_right, null);
    }
    pub fn reset(self: *Self) void {
        self.set_music_data(null, 0, 0, 0, 0);
    }
};
pub const SfxPos = extern struct {
    wave: u8 = 0,
    volume: u8 = 0,
    chord: u8 = 0,
    pitch: u8 = 0,
};
pub const Voice = struct {
    const Self = @This();
    pub const Status = enum(u2) { stop, play_frame, play };
    pub const vib_data: [32]i32 = @bitCast([32]u32{ 0x0, 0x31f1, 0x61f8, 0x8e3a, 0xb505, 0xd4db, 0xec83, 0xfb15, 0x10000, 0xfb15, 0xec83, 0xd4db, 0xb505, 0x8e3a, 0x61f8, 0x31f1, 0x0, 0xffffce0f, 0xffff9e08, 0xffff71c6, 0xffff4afb, 0xffff2b25, 0xffff137d, 0xffff04eb, 0xffff0000, 0xffff04eb, 0xffff137d, 0xffff2b25, 0xffff4afb, 0xffff71c6, 0xffff9e08, 0xffffce0f });
    pub const note_freqs: [NOTES * OCTAVES + PIANO_START]u16 = [_]u16{ 0x10, 0x11, 0x12, 0x13, 0x15, 0x16, 0x17, 0x18, 0x1a, 0x1c, 0x1d, 0x1f, 0x21, 0x23, 0x25, 0x27, 0x29, 0x2c, 0x2e, 0x31, 0x34, 0x37, 0x3a, 0x3e, 0x41, 0x45, 0x49, 0x4e, 0x52, 0x57, 0x5c, 0x62, 0x68, 0x6e, 0x75, 0x7b, 0x83, 0x8b, 0x93, 0x9c, 0xa5, 0xaf, 0xb9, 0xc4, 0xd0, 0xdc, 0xe9, 0xf7, 0x106, 0x115, 0x126, 0x137, 0x14a, 0x15d, 0x172, 0x188, 0x19f, 0x1b8, 0x1d2, 0x1ee, 0x20b, 0x22a, 0x24b, 0x26e, 0x293, 0x2ba, 0x2e4, 0x310, 0x33f, 0x370, 0x3a4, 0x3dc, 0x417, 0x455, 0x497, 0x4dd, 0x527, 0x575, 0x5c8, 0x620, 0x67d, 0x6e0, 0x749, 0x7b8, 0x82d, 0x8a9, 0x92d, 0x9b9, 0xa4d, 0xaea, 0xb90, 0xc40, 0xcfa, 0xdc0, 0xe91, 0xf6f, 0x105a, 0x1153, 0x125b, 0x1372, 0x149a, 0x15d4, 0x1720, 0x1880 };
    tick: u32 = 0,
    tempo: u8 = 0,
    speed: u8 = 0,
    pattern: ?*const MusicPattern = null,
    rows: u8 = 0,
    row: ?u8 = null,
    channel: u2,
    status: Status = .stop,
    held_note: u32 = 0,
    command_data: CommandData = .{},
    channel_data: ChannelData = .{},

    fn tick2row(self: *const Self, tick: u32) u32 {
        return (tick * @as(u32, @intCast(self.tempo)) * DEFAULT_SPEED) / self.speed / NOTES_PER_MINUTE;
    }

    fn row2tick(self: *const Self, row: u32) u32 {
        return (row * self.speed * NOTES_PER_MINUTE) / self.tempo / DEFAULT_SPEED;
    }

    fn set_pattern(self: *Self, pattern: ?u8, tempo: u8, speed: u8, vol_left: u4, vol_right: u4) void {
        if (pattern) |pat| {
            self.pattern = &music_patterns[pat];
            self.channel_data.set_from_data(null, 0, 0, null, vol_left, vol_right, null);
            self.command_data = .{};
            self.tempo = tempo;
            self.speed = speed;
            self.tick = 0;
            self.row = null;
        } else {
            self.pattern = null;
            self.status = .stop;
            self.command_data = .{};
            self.channel_data.reset();
        }
    }
    fn unset_pattern(self: *Self) void {
        self.set_pattern(null, 0, 0, 15, 15);
    }
    fn sfx_pos(self: *const Self, ticks: u32) u32 {
        return if (self.channel_data.speed > 0)
            ticks * @as(u32, @intCast(1 + self.channel_data.speed))
        else
            ticks / @as(u32, @intCast(1 - self.channel_data.speed));
    }
    pub fn sfx(self: *Self, index: ?u32, anote: u32, pitch: i32) void {
        var note = anote;
        if (self.channel_data.duration) |*duration| {
            if (duration.* > 0) {
                duration.* -= 1;
            }
            if (duration.* == 0) {
                self.channel_data.sfx_pos = .{};
                return;
            }
        }
        const idx = index orelse {
            self.channel_data.sfx_pos = .{};
            return;
        };

        const effect = sfx_samples[idx];
        self.channel_data.tick += 1;
        const pos = self.sfx_pos(self.channel_data.tick);

        for (0..@sizeOf(SfxPos)) |i| {
            @as(*[4]u8, @ptrCast(&self.channel_data.sfx_pos))[i] = @truncate(effect.loops.loops[i].calc_loop(pos));
        }

        const volume: u4 = MAX_VOLUME - effect.sequence[self.channel_data.sfx_pos.volume].volume;

        if (volume > 0) {
            const arp: i8 = effect.sequence[self.channel_data.sfx_pos.chord].chord * @as(i8, if (effect.info.reverse) -1 else 1);
            if (arp != 0) note = @intCast(@as(i32, @intCast(note)) + arp);

            note = std.math.clamp(note, 0, @as(u32, @intCast(note_freqs.len - 1)));

            channels[self.channel].fv.frequency = @truncate(note_freqs[note] +% @as(u32, @bitCast(effect.sequence[self.channel_data.sfx_pos.pitch].pitch * @as(i12, if (effect.info.pitch16x) 16 else 1) + pitch)));
            channels[self.channel].fv.volume = volume;

            const wave = effect.sequence[self.channel_data.sfx_pos.wave].wave;
            const waveform = &waveforms[wave];
            std.mem.copyForwards(u8, &channels[self.channel].waveform, waveform);

            const channel_vol = &stereo_volume[self.channel];

            channel_vol.left = self.channel_data.volume.left * @as(u4, @intFromBool(!effect.info.stereo_left));
            channel_vol.right = self.channel_data.volume.right * @as(u4, @intFromBool(!effect.info.stereo_right));
            // channel_vol.left = MAX_VOLUME * @as(u4, @intFromBool(!effect.info.stereo_left));
            // channel_vol.right = MAX_VOLUME * @as(u4, @intFromBool(!effect.info.stereo_right));
        }
    }
    const PlayArgs = struct { volume: u4 = 15, volumeLeft: u4 = 15, volumeRight: u4 = 15, tempo: u8 = 120, speed: u8 = 3 };
    pub fn play(self: *Self, pattern: ?u8, args: PlayArgs) void {
        var largs = args;
        if (largs.volume != MAX_VOLUME) {
            largs.volumeLeft = largs.volume;
            largs.volumeRight = largs.volume;
        }
        self.set_pattern(pattern, largs.tempo, largs.speed, largs.volumeLeft, largs.volumeRight);
        if (pattern) |_| {
            self.status = .play;
        }
    }
    pub fn process(self: *Self) void {
        if (self.status == .stop) return;

        const pattern = self.pattern orelse return;
        const row = self.tick2row(self.tick);

        const rows = MUSIC_PATTERN_ROWS - self.rows;

        if (row >= rows) {
            // : (
            self.set_pattern(null, 0, 0, 15, 15);
            return;
        }

        if (@as(?u8, @as(u8, @intCast(row))) != self.row) skip_delay: {
            self.row = @intCast(row);
            var track_row: TrackRow = pattern.get(row);

            if (track_row.command == .delay) {
                self.command_data.delay.row = track_row;
                self.command_data.delay.ticks = track_row.param2val();
            }

            if (self.command_data.delay.row) |cmd_row| {
                if (self.command_data.delay.ticks == 0) {
                    track_row = cmd_row;
                    self.command_data.delay.row = null;
                } else {
                    break :skip_delay;
                }
            }

            if (track_row.note > 0) {
                self.command_data.slide.tick = 0;
                self.command_data.slide.note = self.channel_data.note;
            }
            if (track_row.note == NOTE_STOP) {
                self.channel_data.set_music_data(null, 0, 0, self.channel_data.volume.left, self.channel_data.volume.right);
            } else if (track_row.note >= NOTE_START) {
                self.channel_data.set_music_data(track_row.sfx(), track_row.note - NOTE_START, track_row.octave, self.channel_data.volume.left, self.channel_data.volume.right);
            }

            switch (track_row.command) {
                .volume => {
                    self.channel_data.volume.left = track_row.param1;
                    self.channel_data.volume.right = track_row.param2;
                },
                .chord => {
                    self.command_data.chord.tick = 0;
                    self.command_data.chord.note1 = track_row.param1;
                    self.command_data.chord.note2 = track_row.param2;
                },
                .jump => {
                    // ???
                },
                .vibrato => {
                    self.command_data.vibrato.tick = 0;
                    self.command_data.vibrato.period = track_row.param1;
                    self.command_data.vibrato.depth = track_row.param2;
                },
                .slide => {
                    self.command_data.slide.duration = track_row.param2val();
                },
                .pitch => {
                    self.command_data.finepitch.value = track_row.param2val() - PITCH_DELTA;
                },
                else => {},
            }
        }

        if (self.channel_data.sfx_index) |sfx_index| {
            var note = self.channel_data.note;
            var pitch: i32 = 0;

            {
                const chord = [_]u4{ 0, self.command_data.chord.note1, self.command_data.chord.note2 };

                note += chord[self.command_data.chord.tick % @as(usize, if (self.command_data.chord.note2 == 0) 2 else 3)];
            }

            if (self.command_data.vibrato.period > 0 and self.command_data.vibrato.depth > 0) {
                const p: u32 = self.command_data.vibrato.period << 1;
                pitch += (vib_data[(self.command_data.vibrato.tick % p) * vib_data.len / p] *% self.command_data.vibrato.depth) >> 16;
            }

            if (self.command_data.slide.tick < self.command_data.slide.duration) {
                pitch += @divTrunc((@as(i32, note_freqs[self.channel_data.note]) - @as(i32, note_freqs[
                    note: {
                        note = self.command_data.slide.note;
                        break :note note;
                    }
                ])) * @as(i32, @intCast(self.command_data.slide.tick)), @as(i32, @intCast(self.command_data.slide.duration)));
            }
            pitch += self.command_data.finepitch.value;

            self.sfx(sfx_index, note, pitch);
        }

        self.command_data.chord.tick += 1;
        self.command_data.vibrato.tick += 1;
        self.command_data.slide.tick += 1;

        if (self.command_data.delay.ticks > 0)
            self.command_data.delay.ticks -= 1;

        self.tick += 1;
    }
};
