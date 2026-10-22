# CTags Plugin

Just open the micro command using Ctrl-E then enter "ctags".

```text
> ctags
```

If the current buffer is a supported type, you will be presented with a list of functions,
classes and/or headings found in the file.

Press Enter to choose the tag to jump to, or ESC to cancel.

Save the buffer before running ctags. Unnamed buffers and unsaved changes are
rejected because tags are read from the file on disk.

Selected text initializes the fuzzy query. Otherwise the word under the cursor
is used. Enter "ctags query text" to supply a query explicitly. Clear the query
in fzf to browse every tag. Tag names and complete signatures are displayed
without parent scope prefixes.

Enter "ctags-back" to return to the previous location in the current file.
History keeps at most 100 locations per file and is cleared on buffer close.
After edits, old positions are clamped to the buffer; they do not track edits.

Settings (change using "set option value"):

	ctags.executable  ctags     Universal Ctags executable name or full path
	ctags.fzf         fzf       fzf executable name or full path
	ctags.sort        foldcase  foldcase, yes, or no (ctags emission order)
	ctags.wordquery   true      Initialize the query from the current word

Executable settings accept paths without arguments. Paths may contain spaces.
Set ctags.wordquery to false to browse all tags when there is no selection.
The picker preserves ctags ordering rather than sorting matches by fuzzy score.

Universal Ctags with JSON support and fzf 0.60.2 or newer are required. Tools are
checked when the command runs. Global fzf options are isolated for this picker.
