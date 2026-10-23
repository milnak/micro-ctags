# micro-ctags - Jump functionality

The ctags plugin for the [micro editor](https://github.com/micro-editor/micro) provides "tags" lookup for any function,
class or heading with jump functionality to go directly to the selected line.

## Supports multiple platforms

This plugin has been tested on Windows and Linux.

## Supports many languages

Supports all languages supported by ctags.

For example, Universal Ctags 6.1.0 supports:

```text
Abaqus, Abc, Ada, AnsiblePlaybook, Ant, Asciidoc, Asm, Asp, Autoconf, AutoIt, Automake, Awk, Basic, Bats, BETA,
BibLaTeX, BibTeX, C, C#, C++, Clojure, CMake, Cobol, CobolFree, CobolVariable, CPreProcessor, CSS, Ctags, CUDA, D,
DBusIntrospect, Diff, DosBatch, DTD, DTS, Eiffel, Elixir, Elm, EmacsLisp, Erlang, Falcon, Flex, Forth, Fortran,
FrontMatter, FunctionParameters, Fypp, Gdbinit, GDScript, GemSpec, Glade, Go, GPerf, Haskell, Haxe, HTML, I18nRubyGem,
Iniconf, Inko, IPythonCell, ITcl, Java, JavaProperties, JavaScript, JSON, Julia, Kconfig, Kotlin, LdScript, LEX, Lisp,
LiterateHaskell, Lua, M4, Make, Man, Markdown, MatLab, Maven2, Meson, MesonOptions, Moose, Myrddin, NSIS, ObjectiveC,
OCaml, OpenAPI, Org, Pascal, Passwd, Perl, Perl6, PHP, PkgConfig, PlistXML, Pod, PowerShell, Protobuf, PuppetManifest,
Python, PythonLoggingConfig, QemuHX, QtMoc, Quarto, R, R6Class, Rake, Raku, RDoc, RelaxNG, ReStructuredText, REXX,
RMarkdown, Robot, RpmMacros, RpmSpec, RSpec, Ruby, Rust, S4Class, Scheme, SCSS, Sh, SLang, SML, SQL, SVG, SystemdUnit,
SystemTap, SystemVerilog, Tcl, TclOO, Terraform, TerraformVariables, Tex, TeXBeamer, Thrift, TTCN, Txt2tags, TypeScript,
V, Varlink, Vera, Verilog, VHDL, Vim, WindRes, XML, XRC, XSLT, YACC, Yaml, YumRepo, Zephir, Zsh
```

## Install

### Debian

```bash
sudo apt-get update
sudo apt-get -y install micro

# universal-ctags (not exuberant-ctags) is required.
sudo apt-get -y remove exuberant-ctags
sudo apt-get -y install universal-ctags

# Install latest version of fzf from GitHub API - Requires fzf 0.60.2 or newer.
FZF_VERSION=$(curl -s "https://api.github.com/repos/junegunn/fzf/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget -qO fzf.tar.gz "https://github.com/junegunn/fzf/releases/latest/download/fzf-$FZF_VERSION-linux_amd64.tar.gz"
sudo tar xf fzf.tar.gz -C /usr/local/bin
rm fzf.tar.gz
```

### Windows

```PowerShell
winget install --exact --id zyedidia.micro
winget install --exact --id junegunn.fzf
winget install --exact --id UniversalCtags.Ctags
```

### All platforms

```bash
mkdir ~/.config/micro/plug
git clone https://github.com/milnak/micro-ctags ~/.config/micro/plug/ctags
```

("micro --plugin install ctags" functionality coming soon)

## Usage

Use "Ctrl-E > ctags" to jump.

Save the buffer first. The plugin reads the file on disk and refuses to navigate
an unnamed or modified buffer, so line numbers cannot silently refer to an older
saved version.

Selected text becomes the initial fuzzy query. With no selection, the word under
the cursor is used instead. Use `ctags query text` to supply an explicit query, or
set `ctags.wordquery` to `false` to browse all tags by default. Clear the query in
fzf to see all tags. Enter jumps; Escape cancels quietly.

Tags display their name and complete signature, without parent scope prefixes.
Use `ctags-back` to return to the previous location in the current file. Up to 100
locations are retained per file until the buffer closes. Positions are clamped to
the current buffer when returning after edits; history does not track text edits.

## Settings

Set these options using Micro's `set` command or `settings.json`:

| Option | Default | Description |
| --- | --- | --- |
| `ctags.executable` | `ctags` | Universal Ctags executable name or full path, without arguments. |
| `ctags.fzf` | `fzf` | fzf executable name or full path, without arguments. |
| `ctags.sort` | `foldcase` | `foldcase`: case-insensitive name order; `yes`: case-sensitive name order; `no`: ctags emission order. |
| `ctags.wordquery` | `true` | Initialize the query from the word under the cursor when there is no selection or explicit query. |

For example, `set ctags.sort no` preserves the order emitted by ctags. The picker
does not reorder matches by fuzzy score. Tool availability and fzf's minimum
version (0.60.2) are checked when `ctags` runs, so settings can be changed without
restarting Micro.

The picker temporarily overrides `FZF_DEFAULT_COMMAND`, `FZF_DEFAULT_OPTS`,
`FZF_DEFAULT_OPTS_FILE`, and `MICRO_CTAGS_INPUT`, then restores their values.
On Windows it also temporarily sets `SHELL=cmd.exe` and leaves `--with-shell`
empty, allowing fzf to use its native CMD quoting. Explicit shell overrides
break quoted input commands in fzf 0.74.5.
Global fzf options are intentionally isolated so custom bindings and output
formats cannot interfere with navigation. Micro does not expose environment
unsetting; previously absent variables are restored as empty strings.

## Tests

Run the command-level regression suite from the plugin directory with Lua:

```sh
lua tests/ctags_test.lua
```

The suite mocks Micro's APIs and covers both Windows and Unix command
construction, literal queries, tag validation, signatures, version checks,
cancellation, temporary-file cleanup, settings, and jump history.

On Windows, with Go and fzf installed, also run the real-process integration
check from the plugin directory:

```sh
go test -v ./tests/windows_fzf_test.go
```

This check gives fzf console stdin to exercise `FZF_DEFAULT_COMMAND`, including
input paths containing spaces and shell metacharacters. It skips when no console
is attached. Set `FZF_TEST_EXECUTABLE` to test a specific fzf executable.

## Known issues

If a Scoop ctags shim cannot be executed by Micro on Windows, set
`ctags.executable` to the real executable's full path, or add its installation
directory to the front of `$env:PATH` before starting Micro.

## Contributions

All contributions are welcome by pull request or issue.

## License

See [LICENSE](./LICENSE) for full text.

## Updating archive

When a new version is created, a new archive release can be created using:

`zip -r -9 .\archive\v1.0.0 * -x 'archive/*' -x 'tests/*' -x '.gitignore'`
