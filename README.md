# micro-ctags - Jump functionaltiy

A plugin for micro editor.

Jump to any function, class or heading.

## Supports many languages

Supports all languages supported by ctags.

My installed ctags (Universal Ctags 6.1.0) supports:

* Abaqus
* Abc
* Ada
* AnsiblePlaybook
* Ant
* Asciidoc
* Asm
* Asp
* Autoconf
* AutoIt
* Automake
* Awk
* Basic
* Bats
* BETA
* BibLaTeX
* BibTeX
* C
* C#
* C++
* Clojure
* CMake
* Cobol
* CobolFree
* CobolVariable
* CPreProcessor
* CSS
* Ctags
* CUDA
* D
* DBusIntrospect
* Diff
* DosBatch
* DTD
* DTS
* Eiffel
* Elixir
* Elm
* EmacsLisp
* Erlang
* Falcon
* Flex
* Forth
* Fortran
* FrontMatter
* FunctionParameters
* Fypp
* Gdbinit
* GDScript
* GemSpec
* Glade
* Go
* GPerf
* Haskell
* Haxe
* HTML
* I18nRubyGem
* Iniconf
* Inko
* IPythonCell
* ITcl
* Java
* JavaProperties
* JavaScript
* JSON
* Julia
* Kconfig
* Kotlin
* LdScript
* LEX
* Lisp
* LiterateHaskell
* Lua
* M4
* Make
* Man
* Markdown
* MatLab
* Maven2
* Meson
* MesonOptions
* Moose
* Myrddin
* NSIS
* ObjectiveC
* OCaml
* OpenAPI
* Org
* Pascal
* Passwd
* Perl
* Perl6
* PHP
* PkgConfig
* PlistXML
* Pod
* PowerShell
* Protobuf
* PuppetManifest
* Python
* PythonLoggingConfig
* QemuHX
* QtMoc
* Quarto
* R
* R6Class
* Rake
* Raku
* RDoc
* RelaxNG
* ReStructuredText
* REXX
* RMarkdown
* Robot
* RpmMacros
* RpmSpec
* RSpec
* Ruby
* Rust
* S4Class
* Scheme
* SCSS
* Sh
* SLang
* SML
* SQL
* SVG
* SystemdUnit
* SystemTap
* SystemVerilog
* Tcl
* TclOO
* Terraform
* TerraformVariables
* Tex
* TeXBeamer
* Thrift
* TTCN
* Txt2tags
* TypeScript
* V
* Varlink
* Vera
* Verilog
* VHDL
* Vim
* WindRes
* XML
* XRC
* XSLT
* YACC
* Yaml
* YumRepo
* Zephir
* Zsh

## Install

### Debian

```bash
sudo apt-get update
sudo apt-get -y install micro fzf exuberant-ctags
```

### Windows

```PowerShell
winget install --exact --id zyedidia.micro
winget install --exact --id junegunn.fzf
winget install --exact --id UniversalCtags.Ctags
```

Copy contents of this folder to `~\.config\micro\plug\ctags`

"micro --plugin install ctags" coming soon.

## Usage

Use "Ctrl-E > ctags" to jump.

## Example

```bash
micro test.py
```

Write some code, e.g.

```python
def hello():
    print("hello")

def bar():
    print("bar")

def foo():
    print("foo")
```

Ctrl-S Save.

Press Ctrl-E > ctags to jump. Use up and down arrows to select a function.

You can also type part of the name.

Press enter to jump.

## Debugging

use `micro -debug <file>` to write micro log file to "log.txt".

## Known issues

On Windows, fzf.exe window isn't always getting focus.
