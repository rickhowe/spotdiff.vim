" spotdiff.vim : A range selectable diffthis to compare partially
"
" Last Change:	2019/08/28
" Version:		3.2
" Author:		Rick Howe <rdcxy754@ybb.ne.jp>
" Copyright:	(c) 2014-2019 by Rick Howe

if exists('g:loaded_spotdiff') || !has('diff') || v:version < 800
	finish
endif
let g:loaded_spotdiff = 3.2

let s:save_cpo = &cpoptions
set cpo&vim

command! -range -bang -bar
				\ Diffthis call spotdiff#Diffthis(<line1>, <line2>, <bang>0)
command! -bang -bar Diffoff call spotdiff#Diffoff(<bang>0)
command! -bang -bar Diffupdate call spotdiff#Diffupdate(<bang>0)

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
