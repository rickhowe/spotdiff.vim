" spotdiff.vim : A range selectable diffthis
"
" Last Change: 2017/01/06
" Version:     1.0
" Author:      Rick Howe <rdcxy754@ybb.ne.jp>

let s:save_cpo = &cpo
set cpo&vim

if !exists('g:spotdiff_signs')
	let g:spotdiff_signs = {'1': {'text': '|', 'texthl': 'Search'},
			\'2': {'text': '|', 'texthl': 'MatchParen'}}
endif

augroup spotdiff
au!
augroup END

function! spotdiff#Diffthis(line1, line2)
	" if original diffthis/diffoff may be used, do nothing with an error
	let dtb = []
	for w in range(1, winnr('$'))
		let id = getwinvar(w, 'SDiff_ID')
		let df = getwinvar(w, '&diff')
		if !empty(id) && !df
			echo w . " has been Diffthis'ed but is not diff mode,
						\ use Diffoff[!] to reset"
			return
		elseif empty(id) && df
			echo w . " is diff mode but has not been Diffthis'ed,
						\ use Diffoff[!] to reset"
			return
		endif
		" save a valid Diffthis'ed bufnr
		if !empty(id) | let dtb += [winbufnr(w)] | endif
	endfor

	" not allow 3 or more Diffthis
	if min(dtb) != max(dtb)
		echo "2 buffers have already been Diffthis'ed,
						\ use Diffoff[!] to reset"
		return
	endif

	if !exists('t:SDiff_Range')
		" the first valid Diffthis
		let t:SDiff_Range = {}
		let id = 1
		let rg = [a:line1 - 1, a:line2 - 1]
	else
		" the second valid Diffthis
		let id = exists('t:SDiff_Range[1]') ? 2 : 1

		if index(dtb, bufnr('%')) == -1
			" on the different buffer
			let rg = [a:line1 - 1, a:line2 - 1]
		else
			" on the same buffer
			let rg = [0, a:line2 -  a:line1]

			" get selected lines and original local options
			let ln = getline(a:line1, a:line2)
			let tn = tempname()
			let save_vop = &l:viewoptions
			let &l:viewoptions = 'options'
			exec 'silent mkview ' . tn
			let &l:viewoptions = save_vop
			let op = join(filter(filter(readfile(tn),
					\'v:val =~ "^setlocal"'),
					\'v:val != "setlocal diff"'), '|')
			call delete(tn)

			" try to create a clone window
			try
				exec (t:SDiff_Range[id == 1 ? 2 : 1][0] <
					\a:line1 ? 'below ' : 'above ') .
						\(winheight(0) / 2) . 'new'
			catch /^Vim(new):E36:/		" no room available
				echohl Error
				echo substitute(v:exception,
							\'^.\{-}:', '', '')
				echohl None
				return
			endtry

			" set the selected lines and original local options
			call setline(1, ln)
			exec op
			" set some specific local options
			let &l:modifiable = 0
			let &l:buftype = 'nofile'

			" set to identify a clone window
			let w:SDiff_Clone = 1
		endif
	endif
	let w:SDiff_ID = id
	let t:SDiff_Range[id] = rg

	" set diffexpr to modify diff input/output files
	if len(t:SDiff_Range) == 2
		let s:save_dex = &diffexpr
		let &diffexpr = 's:DiffthisExpr()'
	endif

	" do diffthis
	silent diffthis

	" restore diffexpr
	if len(t:SDiff_Range) == 2
		let &diffexpr = s:save_dex
		unlet s:save_dex
	endif

	" define sign and replace FoldColumn with it
	exec 'silent sign define SDiff_' . bufnr('%') . '_' . id .
				\' text=' . g:spotdiff_signs[id].text .
				\' texthl=' . g:spotdiff_signs[id].texthl
	let &l:foldcolumn = 0
	for n in range(t:SDiff_Range[id][0] + 1, t:SDiff_Range[id][1] + 1)
		exec 'silent sign place ' . id . ' line=' . n .
				\' name=SDiff_' . bufnr('%') . '_' . id .
					\' buffer=' . bufnr('%')
	endfor

	" set an event
	exec 'au! spotdiff BufWinLeave <buffer=' . bufnr('%') .
					\'> call spotdiff#Diffoff(0)' 
endfunction

function! s:DiffthisExpr()
	let [f_in, f_new] = [readfile(v:fname_in), readfile(v:fname_new)]

	" vim always tries to check a dummy call first
	if f_in == ['line1'] && f_new == ['line2']
		call writefile(['1c1'], v:fname_out)
		return
	endif

	" leave only selected lines in 2 input files
	call writefile(f_in[t:SDiff_Range[1][0] : t:SDiff_Range[1][1]],
								\v:fname_in)
	call writefile(f_new[t:SDiff_Range[2][0] : t:SDiff_Range[2][1]],
								\v:fname_new)

	" execute original or custom diff
	if empty(s:save_dex)
		let opt = '-a --binary '
		if &diffopt =~ 'icase' | let opt .= '-i ' | endif
		if &diffopt =~ 'iwhite' | let opt .= '-b ' | endif
		call writefile(split(system('diff ' . opt . v:fname_in .
				\' ' . v:fname_new), '\n'), v:fname_out)
	else
		call eval(s:save_dex)
	endif

	" modify the line number of diff operations in output file
	let f_out = []
	for dc in filter(readfile(v:fname_out), 'v:val[0] =~ "\\d"')
		let [se1, op, se2] = split(substitute(dc, '\a', ' & ', ''))
		for id in [1, 2]
			let se{id} = join(map(split(se{id}, ','),
					\'v:val + t:SDiff_Range[id][0]'), ',')
		endfor
		let f_out += [se1 . op . se2]
	endfor
	call writefile(f_out, v:fname_out)
endfunction

function! spotdiff#Diffoff(bang)
	let cwin = winnr()

	if a:bang
		" all SDiff windows in reverse
		let wl = filter(range(winnr('$'), 1, -1),
					\'getwinvar(v:val, "SDiff_ID")')
	elseif exists('w:SDiff_ID')
		" current SDiff window first and another clone window next
		let wl = [cwin] + filter(range(1, cwin - 1) +
				\range(cwin + 1, winnr('$')),
					\'getwinvar(v:val, "SDiff_Clone")')
	else
		return
	endif

	for w in wl
		exec 'noautocmd ' . w . 'wincmd w'

		" reset an event
		exec 'au! spotdiff BufWinLeave <buffer=' . bufnr('%') . '>'

		" reset sign and w: value
		exec 'silent sign unplace * buffer=' . bufnr('%')
		exec 'silent sign undefine SDiff_' .
					\bufnr('%') . '_' . w:SDiff_ID
		unlet t:SDiff_Range[w:SDiff_ID]
		unlet w:SDiff_ID

		" do diffoff
		silent diffoff

		" close if this is a clone window
		if exists('w:SDiff_Clone')
			silent quit!
			if cwin > w | let cwin -= 1
			elseif cwin == w | let cwin = winnr()
			endif
		endif

		exec 'noautocmd ' . cwin . 'wincmd w'
	endfor

	" reset t: value
	if exists('t:SDiff_Range') && empty(t:SDiff_Range)
		unlet t:SDiff_Range
	endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
