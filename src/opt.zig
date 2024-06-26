const std = @import("std");
const c = @import("c.zig");
const cc = @import("cc.zig");
const g = @import("g.zig");
const log = @import("log.zig");
const net = @import("net.zig");
const str2int = @import("str2int.zig");
const DynStr = @import("DynStr.zig");
const StrList = @import("StrList.zig");
const Upstream = @import("Upstream.zig");
const cache_ignore = @import("cache_ignore.zig");

const help =
    \\usage: chinadns-ng <options...>. the existing options are as follows:
    \\ -C, --config <path>                  format similar to the long option
    \\ -b, --bind-addr <ip>                 listen address, default: 127.0.0.1
    \\ -l, --bind-port <port>               listen port number, default: 65353
    \\ -c, --china-dns <upstream,...>       china dns server, default: <114 DNS>
    \\ -t, --trust-dns <upstream,...>       trust dns server, default: <Google DNS>
    \\ -m, --chnlist-file <path,...>        path(s) of chnlist, '-' indicate stdin
    \\ -g, --gfwlist-file <path,...>        path(s) of gfwlist, '-' indicate stdin
    \\ -M, --chnlist-first                  match chnlist first, default gfwlist first
    \\ -d, --default-tag <tag>              domain default tag: chn,gfw,none(default)
    \\ -a, --add-tagchn-ip [set4,set6]      add the ip of name-tag:chn to ipset/nft
    \\                                      use '--ipset-name4/6' setname if no value
    \\ -A, --add-taggfw-ip <set4,set6>      add the ip of name-tag:gfw to ipset/nft
    \\ -4, --ipset-name4 <set4>             ip test for tag:none, default: chnroute
    \\ -6, --ipset-name6 <set6>             ip test for tag:none, default: chnroute6
    \\                                      if setname contains @, then use nft-set
    \\                                      format: family_name@table_name@set_name
    \\ -N, --no-ipv6 [rules]                filter AAAA query, rules can be a seq of:
    \\                                      rule a: filter AAAA for all domain
    \\                                      rule m: filter AAAA for tag:chn domain
    \\                                      rule g: filter AAAA for tag:gfw domain
    \\                                      rule n: filter AAAA for tag:none domain
    \\                                      rule c: filter AAAA for china upstream
    \\                                      rule t: filter AAAA for trust upstream
    \\                                      rule C: filter non-chnip reply from china
    \\                                      rule T: filter non-chnip reply from trust
    \\                                      if no rules is given, it defaults to 'a'
    \\ --cache <size>                       enable dns caching, size 0 means disabled
    \\ --cache-stale <N>                    allow use the cached data with a TTL >= -N
    \\ --cache-refresh <N>                  pre-refresh the cached data if the TTL <= N
    \\ --cache-ignore <domain>              ignore the dns cache for this domain(suffix)
    \\ --verdict-cache <size>               enable verdict caching for tag:none domains
    \\ -o, --timeout-sec <sec>              response timeout of upstream, default: 5
    \\ -p, --repeat-times <num>             num of packets to trustdns, default:1, max:5
    \\ -n, --noip-as-chnip                  allow no-ip reply from chinadns (tag:none)
    \\ -f, --fair-mode                      enable fair mode (nop, only fair mode now)
    \\ -r, --reuse-port                     enable SO_REUSEPORT, default: <disabled>
    \\ -v, --verbose                        print the verbose log, default: <disabled>
    \\ -V, --version                        print `chinadns-ng` version number and exit
    \\ -h, --help                           print `chinadns-ng` help information and exit
    \\bug report: https://github.com/zfl9/chinadns-ng. email: zfl9.com@gmail.com (Otokaze)
;

comptime {
    // @compileLog("sizeof(OptDef):", @sizeOf(OptDef), "alignof(OptDef):", @alignOf(OptDef));
    // @compileLog("sizeof([]const u8):", @sizeOf([]const u8), "alignof([]const u8):", @alignOf([]const u8));
    // @compileLog("sizeof(OptFn):", @sizeOf(OptFn), "alignof(OptFn):", @alignOf(OptFn));
    // @compileLog("sizeof(enum{a,b,c}):", @sizeOf(enum { a, b, c }), "alignof(enum{a,b,c}):", @alignOf(enum { a, b, c }));
}

const OptDef = struct {
    short: []const u8, // short name
    long: []const u8, // long name
    optfn: OptFn,
    value: enum { required, optional, no_value },
};

const OptFn = std.meta.FnPtr(fn (in_value: ?[]const u8) void);

// zig fmt: off
const optdef_array = [_]OptDef{
    .{ .short = "C", .long = "config",        .value = .required, .optfn = opt_config,        },
    .{ .short = "b", .long = "bind-addr",     .value = .required, .optfn = opt_bind_addr,     },
    .{ .short = "l", .long = "bind-port",     .value = .required, .optfn = opt_bind_port,     },
    .{ .short = "c", .long = "china-dns",     .value = .required, .optfn = opt_china_dns,     },
    .{ .short = "t", .long = "trust-dns",     .value = .required, .optfn = opt_trust_dns,     },
    .{ .short = "m", .long = "chnlist-file",  .value = .required, .optfn = opt_chnlist_file,  },
    .{ .short = "g", .long = "gfwlist-file",  .value = .required, .optfn = opt_gfwlist_file,  },
    .{ .short = "M", .long = "chnlist-first", .value = .no_value, .optfn = opt_chnlist_first, },
    .{ .short = "d", .long = "default-tag",   .value = .required, .optfn = opt_default_tag,   },
    .{ .short = "a", .long = "add-tagchn-ip", .value = .optional, .optfn = opt_add_tagchn_ip, },
    .{ .short = "A", .long = "add-taggfw-ip", .value = .required, .optfn = opt_add_taggfw_ip, },
    .{ .short = "4", .long = "ipset-name4",   .value = .required, .optfn = opt_ipset_name4,   },
    .{ .short = "6", .long = "ipset-name6",   .value = .required, .optfn = opt_ipset_name6,   },
    .{ .short = "N", .long = "no-ipv6",       .value = .optional, .optfn = opt_no_ipv6,       },
    .{ .short = "",  .long = "cache",         .value = .required, .optfn = opt_cache,         },
    .{ .short = "",  .long = "cache-stale",   .value = .required, .optfn = opt_cache_stale,   },
    .{ .short = "",  .long = "cache-refresh", .value = .required, .optfn = opt_cache_refresh, },
    .{ .short = "",  .long = "cache-ignore",  .value = .required, .optfn = opt_cache_ignore,  },
    .{ .short = "",  .long = "verdict-cache", .value = .required, .optfn = opt_verdict_cache, },
    .{ .short = "o", .long = "timeout-sec",   .value = .required, .optfn = opt_timeout_sec,   },
    .{ .short = "p", .long = "repeat-times",  .value = .required, .optfn = opt_repeat_times,  },
    .{ .short = "n", .long = "noip-as-chnip", .value = .no_value, .optfn = opt_noip_as_chnip, },
    .{ .short = "f", .long = "fair-mode",     .value = .no_value, .optfn = opt_fair_mode,     },
    .{ .short = "r", .long = "reuse-port",    .value = .no_value, .optfn = opt_reuse_port,    },
    .{ .short = "v", .long = "verbose",       .value = .no_value, .optfn = opt_verbose,       },
    .{ .short = "V", .long = "version",       .value = .no_value, .optfn = opt_version,       },
    .{ .short = "h", .long = "help",          .value = .no_value, .optfn = opt_help,          },
};
// zig fmt: on

noinline fn get_optdef(name: []const u8) ?OptDef {
    if (name.len == 0)
        return null;

    for (optdef_array) |optdef| {
        if (std.mem.eql(u8, optdef.short, name) or std.mem.eql(u8, optdef.long, name))
            return optdef;
    }

    return null;
}

// ================================================================

/// print msg
fn print(comptime src: std.builtin.SourceLocation, comptime fmt: [:0]const u8, args: anytype) void {
    cc.printf(log.srcinfo(src) ++ " " ++ fmt ++ "\n", args);
}

/// print msg + print help + exit(1)
fn exit(comptime src: std.builtin.SourceLocation, comptime fmt: [:0]const u8, args: anytype) noreturn {
    cc.printf(log.srcinfo(src) ++ " " ++ fmt ++ "\n", args);
    cc.printf("%s\n", .{help});
    cc.exit(1);
}

/// simple version of `print`
pub fn err_print(comptime src: std.builtin.SourceLocation, msg: [:0]const u8, value: []const u8) void {
    print(src, "%s: '%.*s'", .{ msg.ptr, cc.to_int(value.len), value.ptr });
}

/// simple version of `exit`
fn err_exit(comptime src: std.builtin.SourceLocation, value: []const u8) noreturn {
    exit(src, "invalid opt-value: '%.*s'", .{ cc.to_int(value.len), value.ptr });
}

// ================================================================

fn opt_config(in_value: ?[]const u8) void {
    // prevent stack overflow due to recursion
    const static = struct {
        var depth: u8 = 0;
    };

    const src = @src();
    const value = in_value.?;

    if (static.depth + 1 > 10)
        exit(src, "config chain is too deep: '%.*s'", .{ cc.to_int(value.len), value.ptr });

    static.depth += 1;
    defer static.depth -= 1;

    if (value.len > c.PATH_MAX)
        exit(src, "filename is too long: '%.*s'", .{ cc.to_int(value.len), value.ptr });

    // TODO: vla/alloca allocator
    const filename = cc.strdup(value);
    defer g.allocator.free(filename);

    const file = cc.fopen(filename, "r") orelse
        exit(src, "failed to open the config file: '%s' (%m)", .{filename.ptr});
    defer _ = cc.fclose(file);

    var buf: [512]u8 = undefined;

    while (cc.fgets(file, &buf)) |p_line| {
        const errmsg: cc.ConstStr = e: {
            const line = cc.strslice_c(p_line);

            if (line[line.len - 1] == '\n')
                p_line[line.len - 1] = 0 // remove \n
            else if (!cc.feof(file)) // last line may not have \n
                break :e "line is too long";

            // optname [optvalue]
            var it = std.mem.tokenize(u8, line, " \t\r\n\x00");

            const optname = it.next() orelse continue;

            if (std.mem.startsWith(u8, optname, "#")) continue;

            const optvalue = it.next();

            if (it.next() != null)
                break :e "too many values";

            const optdef = get_optdef(optname) orelse
                break :e "unknown option";

            switch (optdef.value) {
                .required => {
                    if (optvalue == null)
                        break :e "missing opt-value";
                },
                .no_value => {
                    if (optvalue != null)
                        break :e "unexpected opt-value";
                },
                else => {},
            }

            if (optvalue != null and optvalue.?.len <= 0)
                break :e "invalid format";

            optdef.optfn(optvalue);

            continue;
        };

        // error handling
        exit(src, "'%s': %s: %s", .{ filename.ptr, errmsg, p_line });
    }
}

pub noinline fn check_ip(value: []const u8) ?void {
    var buf: [64]u8 = undefined;

    const src = @src();

    const ip = cc.strdup_r(value, &buf) orelse {
        err_print(src, "ip is too long", value);
        return null;
    };

    if (cc.get_ipstr_family(ip.ptr) == null) {
        err_print(src, "invalid ip", value);
        return null;
    }
}

pub noinline fn check_port(value: []const u8) ?u16 {
    const port = str2int.parse(u16, value, 10) orelse 0;
    if (port == 0) {
        err_print(@src(), "invalid port", value);
        return null;
    }
    return port;
}

fn opt_bind_addr(in_value: ?[]const u8) void {
    const value = in_value.?;
    check_ip(value) orelse err_exit(@src(), value);
    g.bind_ips.add(value);
}

fn opt_bind_port(in_value: ?[]const u8) void {
    const value = in_value.?;
    const src = @src();

    // 53 (53@tcp+udp)
    // 53@tcp
    // 53@udp
    // 53@tcp+udp
    var it = std.mem.split(u8, value, "@");

    // port
    const port = it.next().?;
    g.bind_port = check_port(port) orelse err_exit(src, value);

    // proto
    if (it.next()) |proto| {
        if (std.mem.eql(u8, proto, "tcp+udp") or std.mem.eql(u8, proto, "udp+tcp")) {
            g.bind_tcp = true;
            g.bind_udp = true;
        } else if (std.mem.eql(u8, proto, "tcp")) {
            g.bind_tcp = true;
            g.bind_udp = false;
        } else if (std.mem.eql(u8, proto, "udp")) {
            g.bind_tcp = false;
            g.bind_udp = true;
        } else {
            err_exit(src, value);
        }
    } else {
        g.bind_tcp = true;
        g.bind_udp = true;
    }

    if (it.next() != null)
        err_exit(src, value);
}

/// "upstream,..."
noinline fn add_upstreams(group: *Upstream.Group, upstreams: []const u8) ?void {
    var it = std.mem.split(u8, upstreams, ",");
    while (it.next()) |upstream| {
        group.add(upstream) orelse {
            err_print(@src(), "invalid address", upstream);
            return null;
        };
    }
}

fn opt_china_dns(in_value: ?[]const u8) void {
    const value = in_value.?;
    add_upstreams(&g.china_group, value) orelse err_exit(@src(), value);
}

fn opt_trust_dns(in_value: ?[]const u8) void {
    const value = in_value.?;
    add_upstreams(&g.trust_group, value) orelse err_exit(@src(), value);
}

/// "foo.txt,..."
noinline fn add_paths(list: *StrList, paths: []const u8) ?void {
    var it = std.mem.split(u8, paths, ",");
    while (it.next()) |path| {
        const src = @src();
        if (path.len <= 0) {
            err_print(src, "invalid paths format", paths);
            return null;
        }
        if (path.len > c.PATH_MAX) {
            err_print(src, "path is too long", path);
            return null;
        }
        list.add(path);
    }
}

fn opt_chnlist_file(in_value: ?[]const u8) void {
    const value = in_value.?;
    add_paths(&g.chnlist_filenames, value) orelse err_exit(@src(), value);
}

fn opt_gfwlist_file(in_value: ?[]const u8) void {
    const value = in_value.?;
    add_paths(&g.gfwlist_filenames, value) orelse err_exit(@src(), value);
}

fn opt_chnlist_first(_: ?[]const u8) void {
    g.gfwlist_first = false;
}

fn opt_default_tag(in_value: ?[]const u8) void {
    const value = in_value.?;
    const map = .{
        .{ .tagname = "chn", .tag = .chn },
        .{ .tagname = "gfw", .tag = .gfw },
        .{ .tagname = "none", .tag = .none },
    };
    inline for (map) |v| {
        if (std.mem.eql(u8, v.tagname, value)) {
            g.default_tag = v.tag;
            return;
        }
    }
    err_exit(@src(), value);
}

fn opt_add_tagchn_ip(in_value: ?[]const u8) void {
    // empty string means 'no_value'
    g.chnip_setnames.set(in_value orelse "");
}

fn opt_add_taggfw_ip(in_value: ?[]const u8) void {
    g.gfwip_setnames.set(in_value.?);
}

fn opt_ipset_name4(in_value: ?[]const u8) void {
    g.chnroute_name.set(in_value.?);
}

fn opt_ipset_name6(in_value: ?[]const u8) void {
    g.chnroute6_name.set(in_value.?);
}

fn opt_no_ipv6(in_value: ?[]const u8) void {
    if (in_value) |value| {
        for (value) |rule| {
            g.noaaaa_rule.add(switch (rule) {
                'a' => .all,
                'm' => .tag_chn,
                'g' => .tag_gfw,
                'n' => .tag_none,
                'c' => .china_dns,
                't' => .trust_dns,
                'C' => .china_iptest,
                'T' => .trust_iptest,
                else => exit(@src(), "invalid no-aaaa rule: '%c'", .{rule}),
            });
        }
    } else {
        g.noaaaa_rule.add(.all);
    }
}

fn opt_cache(in_value: ?[]const u8) void {
    const value = in_value.?;
    g.cache_size = str2int.parse(@TypeOf(g.cache_size), value, 10) orelse
        err_exit(@src(), value);
}

fn opt_cache_stale(in_value: ?[]const u8) void {
    const value = in_value.?;
    g.cache_stale = str2int.parse(@TypeOf(g.cache_stale), value, 10) orelse
        err_exit(@src(), value);
}

fn opt_cache_refresh(in_value: ?[]const u8) void {
    const value = in_value.?;
    g.cache_refresh = str2int.parse(@TypeOf(g.cache_refresh), value, 10) orelse
        err_exit(@src(), value);
}

fn opt_cache_ignore(in_value: ?[]const u8) void {
    const domain = in_value.?;
    cache_ignore.add(domain) orelse err_exit(@src(), domain);
}

fn opt_verdict_cache(in_value: ?[]const u8) void {
    const value = in_value.?;
    g.verdict_cache_size = str2int.parse(@TypeOf(g.verdict_cache_size), value, 10) orelse
        err_exit(@src(), value);
}

fn opt_timeout_sec(in_value: ?[]const u8) void {
    const value = in_value.?;
    g.upstream_timeout = str2int.parse(@TypeOf(g.upstream_timeout), value, 10) orelse 0;
    if (g.upstream_timeout == 0) err_exit(@src(), value);
}

fn opt_repeat_times(in_value: ?[]const u8) void {
    const value = in_value.?;
    g.trustdns_packet_n = str2int.parse(@TypeOf(g.trustdns_packet_n), value, 10) orelse 0;
    if (g.trustdns_packet_n == 0) err_exit(@src(), value);
    g.trustdns_packet_n = std.math.min(g.trustdns_packet_n, g.TRUSTDNS_PACKET_MAX);
}

fn opt_noip_as_chnip(_: ?[]const u8) void {
    g.noip_as_chnip = true;
}

fn opt_fair_mode(_: ?[]const u8) void {
    // legacy option, deprecated
}

fn opt_reuse_port(_: ?[]const u8) void {
    g.reuse_port = true;
}

fn opt_verbose(_: ?[]const u8) void {
    g.verbose = true;
}

fn opt_version(_: ?[]const u8) void {
    cc.printf("%s\n", .{g.VERSION});
    cc.exit(0);
}

fn opt_help(_: ?[]const u8) void {
    cc.printf("%s\n", .{help});
    cc.exit(0);
}

// ================================================================

const Parser = struct {
    idx: usize,

    pub fn init() Parser {
        return .{ .idx = 1 };
    }

    pub noinline fn parse(self: *Parser) void {
        const arg = self.pop_arg() orelse return;

        const errmsg: cc.ConstStr = e: {
            if (std.mem.startsWith(u8, arg, "--")) {
                if (arg.len < 4)
                    break :e "invalid long option";

                // --name
                // --name=value
                // --name value
                if (std.mem.indexOfScalar(u8, arg, '=')) |sep|
                    self.handle(arg[2..sep], arg[sep + 1 ..])
                else
                    self.handle(arg[2..], null);
                //
            } else if (std.mem.startsWith(u8, arg, "-")) {
                if (arg.len < 2)
                    break :e "invalid short option";

                // -x
                // -x5
                // -x=5
                // -x 5
                if (arg.len == 2)
                    self.handle(arg[1..], null)
                else if (arg[2] == '=')
                    self.handle(arg[1..2], arg[3..])
                else
                    self.handle(arg[1..2], arg[2..]);
                //
            } else {
                break :e "expect an option, got the pos-argument";
            }

            return @call(.{ .modifier = .always_tail }, Parser.parse, .{self});
        };

        // error handling
        exit(@src(), "%s: '%s'", .{ errmsg, arg.ptr });
    }

    noinline fn peek_arg(self: Parser) ?[:0]const u8 {
        const argv = std.os.argv;

        return if (self.idx < argv.len)
            std.mem.sliceTo(argv[self.idx], 0)
        else
            null;
    }

    noinline fn pop_arg(self: *Parser) ?[:0]const u8 {
        if (self.peek_arg()) |arg| {
            self.idx += 1;
            return arg;
        }
        return null;
    }

    noinline fn take_value(self: *Parser, name: []const u8, required: bool) ?[:0]const u8 {
        const arg = self.peek_arg() orelse {
            if (required)
                exit(@src(), "expect a value for option '%.*s'", .{ cc.to_int(name.len), name.ptr });
            return null;
        };

        if (required or !std.mem.startsWith(u8, arg, "-")) {
            _ = self.pop_arg();
            return arg;
        }

        return null;
    }

    noinline fn handle(self: *Parser, name: []const u8, in_value: ?[:0]const u8) void {
        const src = @src();

        const optdef = get_optdef(name) orelse
            exit(src, "unknown option: '%.*s'", .{ cc.to_int(name.len), name.ptr });

        const value = switch (optdef.value) {
            .required => if (in_value) |v| v else self.take_value(name, true),
            .optional => if (in_value) |v| v else self.take_value(name, false),
            .no_value => if (in_value == null) null else {
                exit(src, "option '%.*s' does not accept any values: '%s'", .{ cc.to_int(name.len), name.ptr, in_value.?.ptr });
            },
        };

        if (value != null and value.?.len <= 0)
            exit(src, "option '%.*s' does not accept empty string", .{ cc.to_int(name.len), name.ptr });

        optdef.optfn(value);
    }
};

// ================================================================

pub fn parse() void {
    @setCold(true);

    var parser = Parser.init();
    parser.parse();

    if (g.chnroute_name.is_null())
        g.chnroute_name.set("chnroute");

    if (g.chnroute6_name.is_null())
        g.chnroute6_name.set("chnroute6");

    if (!g.chnip_setnames.is_null() and g.chnip_setnames.is_empty())
        g.chnip_setnames.set_ex(&.{ g.chnroute_name.str, ",", g.chnroute6_name.str });

    if (g.bind_ips.is_null())
        g.bind_ips.add("127.0.0.1");

    if (g.china_group.is_empty())
        g.china_group.add("114.114.114.114") orelse unreachable;

    if (g.trust_group.is_empty())
        g.trust_group.add("8.8.8.8") orelse unreachable;
}

pub fn @"test: opt"() !void {
    _ = parse;
}
