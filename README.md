# micro-ctags - Jump functionaltiy

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
sudo apt-get -y install micro exuberant-ctags

# Get latest version from GitHub API - Requires fzf 0.60.2 or newer.
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

("micro --plugin install ctags" coming soon)

## Usage

Use "Ctrl-E > ctags" to jump.

## Debugging

use `micro -debug <file>` to write micro log file to "log.txt".

## Known issues

On Windows, fzf.exe window isn't always getting focus.
