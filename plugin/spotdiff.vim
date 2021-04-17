" spotdiff.vim : A range and area selectable diffthis to compare partially
"
" Last Change:	2021/04/17
" Version:		4.0
" Author:		Rick Howe <rdcxy754@ybb.ne.jp>
" Copyright:	(c) 2014-2021 by Rick Howe

if exists('g:loaded_spotdiff') || !has('diff') || v:version < 800
	finish
endif
let g:loaded_spotdiff = 4.0

let s:save_cpo = &cpoptions
set cpo&vim

command! -range -bang -bar Diffthis call spotdiff#Diffthis(<line1>, <line2>)
command! -range -bang -bar Diffoff call spotdiff#Diffoff(<bang>0)
command! -bang -bar Diffupdate call spotdiff#Diffupdate(<bang>0)

command! -range -bang -bar
				\ VDiffthis call spotdiff#VDiffthis(<line1>, <line2>, <bang>0)
command! -range=% -bang -bar
				\ VDiffoff call spotdiff#VDiffoff(<bang>0, <line1>, <line2>)
command! -bang -bar VDiffupdate call spotdiff#VDiffupdate()

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
