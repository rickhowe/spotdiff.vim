" spotdiff.vim : A range and area selectable diffthis to compare partially
"
" Last Change: 2023/03/26
" Version:     5.0
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2014-2023 by Rick Howe
" License:     MIT

if exists('g:loaded_spotdiff') || !has('diff') ||
                                    \!(802 <= v:version || has('nvim-0.4.4'))
  finish
endif
let g:loaded_spotdiff = 5.0

let s:save_cpo = &cpoptions
set cpo&vim

command! -range -bar Diffthis call spotdiff#Diffthis(<line1>, <line2>)
command! -bang -bar Diffoff call spotdiff#Diffoff(<bang>0)
command! -bar Diffupdate call spotdiff#Diffupdate()

command! -range -bang -bar
                \ VDiffthis call spotdiff#VDiffthis(<line1>, <line2>, <bang>0)
command! -bang -bar VDiffoff call spotdiff#VDiffoff(<bang>0)
command! -bar VDiffupdate call spotdiff#VDiffupdate()

for [mod, key, plg, cmd] in [
  \['v', '<Leader>t', '<Plug>(VDiffthis)',
          \':<C-U>call spotdiff#VDiffthis(line("''<"), line("''>"), 0)<CR>'],
  \['v', '<Leader>T', '<Plug>(VDiffthis!)',
          \':<C-U>call spotdiff#VDiffthis(line("''<"), line("''>"), 1)<CR>'],
  \['n', '<Leader>o', '<Plug>(VDiffoff)',
                                      \':<C-U>call spotdiff#VDiffoff(0)<CR>'],
  \['n', '<Leader>O', '<Plug>(VDiffoff!)',
                                      \':<C-U>call spotdiff#VDiffoff(1)<CR>'],
  \['n', '<Leader>u', '<Plug>(VDiffupdate)',
                                    \':<C-U>call spotdiff#VDiffupdate()<CR>'],
  \['n', '<Leader>t', '<Plug>(VDiffthis)',
                        \':let &operatorfunc = ''<SID>VDiffOpFunc0''<CR>g@'],
  \['n', '<Leader>T', '<Plug>(VDiffthis!)',
                        \':let &operatorfunc = ''<SID>VDiffOpFunc1''<CR>g@']]
  if !hasmapto(plg, mod) && empty(maparg(key, mod))
    if get(g:, 'VDiffDoMapping', 1)
      call execute(mod . 'map <silent> ' . key . ' ' . plg)
    endif
  endif
  call execute(mod . 'noremap <silent> ' . plg . ' ' . cmd)
endfor

function! s:VDiffOpFunc0(vm) abort
  call spotdiff#VDiffOpFunc(a:vm, 0)
endfunction

function! s:VDiffOpFunc1(vm) abort
  call spotdiff#VDiffOpFunc(a:vm, 1)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
