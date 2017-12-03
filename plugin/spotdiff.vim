" spotdiff.vim : A range selectable diffthis to compare partially
"
" Last Change: 2017/12/03
" Version:     2.2
" Author:      Rick Howe <rdcxy754@ybb.ne.jp>

if exists('g:loaded_spotdiff') || !has('diff') || v:version < 704
	finish
endif
let g:loaded_spotdiff = 2.2

let s:save_cpo = &cpoptions
set cpo&vim

command! -range -bang -bar
				\ Diffthis call spotdiff#Diffthis(<line1>, <line2>, <bang>0)
command! -bang -bar Diffoff call spotdiff#Diffoff(<bang>0)
command! -bang -bar Diffupdate call spotdiff#Diffupdate(<bang>0)

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
