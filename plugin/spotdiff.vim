" spotdiff.vim : A range selectable diffthis to compare any lines in buffers
"
" Last Change: 2017/01/26
" Version:     1.1
" Author:      Rick Howe <rdcxy754@ybb.ne.jp>

if exists('g:loaded_spotdiff') || v:version < 704
	finish
endif
let g:loaded_spotdiff = 1.1

let s:save_cpo = &cpo
set cpo&vim

command! -bar -range Diffthis call spotdiff#Diffthis(<line1>, <line2>)
command! -bar -bang  Diffoff  call spotdiff#Diffoff(<bang>0)

let &cpo = s:save_cpo
unlet s:save_cpo
