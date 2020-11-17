const std = @import("std");
const mem = std.mem;
const print = std.debug.print;
const fs = std.fs;
const ChildProcess = std.ChildProcess;
const process = std.process;

const render_utils = @import("render_utils.zig");

pub const RunCommand = struct {
    expected_outcome: enum { Success, Failure } = .Success,
    check_output: ?[]const u8 = null, // TODO: should we differentiate between out and err?
    max_doc_file_size: usize = 1024 * 1024 * 1, // 1MB TODO: change?
    // TODO: arguments?
};

pub fn runExe(
    allocator: *mem.Allocator,
    path_to_exe: []const u8,
    out: anytype,
    env_map: *std.BufMap,
    cmd: RunCommand,
) !void {
    const run_args = &[_][]const u8{path_to_exe};
    var exited_with_signal = false;

    const result = if (cmd.expected_outcome == .Failure) ko: {
        const result = try ChildProcess.exec(.{
            .allocator = allocator,
            .argv = run_args,
            .env_map = env_map,
            .max_output_bytes = cmd.max_doc_file_size,
        });

        switch (result.term) {
            .Exited => |exit_code| {
                if (exit_code == 0) {
                    print("{}\nThe following command incorrectly succeeded:\n", .{result.stderr});
                    render_utils.dumpArgs(run_args);
                    // return parseError(tokenizer, code.source_token, "example incorrectly compiled", .{});
                    return;
                }
            },
            .Signal => exited_with_signal = true,
            else => {},
        }
        break :ko result;
    } else ok: {
        break :ok try exec(allocator, env_map, cmd.max_doc_file_size, run_args);
    };

    const escaped_stderr = try render_utils.escapeHtml(allocator, result.stderr);
    const escaped_stdout = try render_utils.escapeHtml(allocator, result.stdout);

    const colored_stderr = try render_utils.termColor(allocator, escaped_stderr);
    const colored_stdout = try render_utils.termColor(allocator, escaped_stdout);

    try out.print("\n$ ./{}\n{}{}", .{ fs.path.basename(path_to_exe), colored_stdout, colored_stderr });
    if (exited_with_signal) {
        try out.print("(process terminated by signal)", .{});
    }
    try out.print("</code></pre>\n", .{});
}

fn exec(allocator: *mem.Allocator, env_map: *std.BufMap, max_size: usize, args: []const []const u8) !ChildProcess.ExecResult {
    const result = try ChildProcess.exec(.{
        .allocator = allocator,
        .argv = args,
        .env_map = env_map,
        .max_output_bytes = max_size,
    });
    switch (result.term) {
        .Exited => |exit_code| {
            if (exit_code != 0) {
                print("{}\nThe following command exited with code {}:\n", .{ result.stderr, exit_code });
                render_utils.dumpArgs(args);
                return error.ChildExitError;
            }
        },
        else => {
            print("{}\nThe following command crashed:\n", .{result.stderr});
            render_utils.dumpArgs(args);
            return error.ChildCrashed;
        },
    }
    return result;
}