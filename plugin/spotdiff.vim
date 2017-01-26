" spotdiff.vim : A range selectable diffthis
"
" Last Change: 2017/01/06
" Version:     1.0
" Author:      Rick Howe <rdcxy754@ybb.ne.jp>

if exists('g:loaded_spotdiff') || v:version < 704
	finish
endif
let g:loaded_spotdiff = 1.0

let s:save_cpo = &cpo
set cpo&vim

command! -range Diffthis call spotdiff#Diffthis(<line1>, <line2>)
command! -bang  Diffoff  call spotdiff#Diffoff(<bang>0)

let &cpo = s:save_cpo
unlet s:save_cpo
