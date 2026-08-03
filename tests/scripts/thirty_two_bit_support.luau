-- this tests asserts we didn't forget to convert any LuaInteger(i) => i cases to LuaInteger(i) => int_to_i64(i)

const fs = require("@std/fs")
const str = require("@std/str")

const rust_files = fs.listdir("./src", true, function(path)
    return str.endswith(path, ".rs")
end)

type OffendingLine = {
    file: string,
    line: string,
    line_number: number,
}


const offending_lines: { OffendingLine } = {}
const function push_offender(path: string, line: string, line_number: number)
    table.insert(offending_lines, {
        file = path,
        line = str.trimfront(line),
        line_number = line_number
    })
end
const function format_offender(self: OffendingLine): string
    return `- {self.file}:{self.line_number}: {self.line}`
end

for _, file in rust_files do
    for line_number, line in fs.readlines(file) do
        const variable_name, raw_rhs = string.match(line, "LuaValue::Integer%(([%w_]+)%)%s*=>%s*(.-)%s*$")
        if not variable_name or not raw_rhs then
            continue
        end

        const rhs = if string.sub(raw_rhs, -1) == "," then string.sub(raw_rhs, 1, -2) else raw_rhs
        const bare_passthrough = variable_name
        const wrapped_in_some = `Some({variable_name})`

        if rhs == bare_passthrough or rhs == wrapped_in_some then
            push_offender(file, line, line_number)
        end
    end
end

if #offending_lines > 0 then
    const lines = {}
    for _, l in offending_lines do
        table.insert(lines, format_offender(l))
    end
    error(`32-bit compatibility regression: fix these:\n{table.concat(lines, "\n")}`)
end
