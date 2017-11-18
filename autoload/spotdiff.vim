" spotdiff.vim : A range selectable diffthis to compare partially
"
" Last Change: 2017/11/18
" Version:     2.0
" Author:      Rick Howe <rdcxy754@ybb.ne.jp>

let s:save_cpo = &cpoptions
set cpo&vim

function! spotdiff#Diffthis(line1, line2, conceal)
	call s:RepairSpotDiff()
	let sw = filter(range(1, winnr('$')),
									\'!empty(getwinvar(v:val, "SDiff", {}))')
	if 2 <= len(sw)
		echohl Error
		echo '2 windows have already been Diffthis''ed!
										\ Use Diffoff[!] to reset either/all.'
		echohl None
		return
	endif
	call s:ToggleSpotDiff(1)
	if empty(sw)
		" the first valid Diffthis
		let [id, rg, cl] = [1, [a:line1, a:line2], 0]
	else
		" the second valid Diffthis
		let sd = getwinvar(sw[0], 'SDiff')
		let id = (sd.id == 1) ? 2 : 1
		if winbufnr(sw[0]) != bufnr('%')
			" on the different buffer
			let [rg, cl] = [[a:line1, a:line2], 0]
		else
			" on the same buffer
			let [rg, cl] = [[1, a:line2 - a:line1 + 1] , 1]
			" get selected text and original local options
			let tx = getline(a:line1, a:line2)
			let wo = getwinvar(winnr(), '&')
			let bo = getbufvar(bufnr('%'), '&')
			" try to create a clone window
			try
				execute (sd.range[0] < a:line1 ? 'below ' : 'above ') .
							\min([(winheight(0) - 1) / 2, len(tx)]) . 'new'
			catch /^Vim(new):E36:/				" not enough room
				echohl Error
				echo substitute(v:exception, '^.\{-}:', '', '')
				echohl None
				return
			endtry
			" set the selected text and original local options
			call setline(1, tx)
			call map(filter(wo, 'v:key != "diff"'),
									\'setwinvar(winnr(), "&" . v:key, v:val)')
			call map(bo, 'setbufvar(bufnr("%"), "&" . v:key, v:val)')
			" set some specific local options
			let &l:modifiable = 0
			let &l:buftype = 'nofile'
		endif
	endif
	" set SDiff dictionary in this window
	let w:SDiff = {'id': id, 'range': rg, 'clone': cl, 'conceal': 0}
	" set diffexpr to modify diff input/output files
	let s:save_dex = &diffexpr
	let &diffexpr = 's:SpotDiffExpr()'
	silent diffthis
	let &diffexpr = s:save_dex
	unlet s:save_dex
	" highlight other lines than selected with Conceal
	if a:conceal && has('conceal')
		let w:SDiff.conceal = matchadd('Conceal', '\%<' . w:SDiff.range[0] .
								\'l\|' . '\%>' . w:SDiff.range[1] . 'l', -100)
	endif
	call s:ShowFoldSign()
endfunction

function! spotdiff#Diffoff(all)
	call s:RepairSpotDiff()
	let sw = filter(range(1, winnr('$')),
									\'!empty(getwinvar(v:val, "SDiff", {}))')
	if empty(sw) | return | endif
	let cw = winnr()
	if !a:all
		if index(sw, cw) != -1 | let sw = [cw]
		else | return
		endif
	endif
	for w in sw
		execute 'noautocmd ' . w . 'wincmd w'
		silent diffoff
		if w:SDiff.conceal
			if index(map(getmatches(), 'v:val.id'), w:SDiff.conceal) != -1
				call matchdelete(w:SDiff.conceal)
			endif
		endif
		" remember a clone window to quit later
		if w:SDiff.clone | let cl = w | endif
		unlet w:SDiff
	endfor
	execute 'noautocmd ' . cw . 'wincmd w'
	if a:all | silent diffoff! | endif
	call s:ToggleSpotDiff(0)
	" quit the clone window
	if exists('cl')
		execute 'noautocmd ' . cl . 'wincmd w'
		silent quit!
		if cl < cw | let cw -= 1
		elseif cl == cw | let cw = winnr()
		endif
	endif
	execute 'noautocmd ' . cw . 'wincmd w'
	call s:ShowFoldSign()
endfunction

function! s:ShowFoldSign()
	" show fold sign (-) at each selected lines on all sdiff windows
	let cw = winnr()
	for sw in filter(range(1, winnr('$')),
									\'!empty(getwinvar(v:val, "SDiff", {}))')
		execute 'noautocmd ' . sw . 'wincmd w'
		let &l:foldmethod = 'diff'
		let &l:foldmethod = 'manual'
		for l in range(w:SDiff.range[0], w:SDiff.range[1])
			execute 'silent ' l . 'fold'
		endfor
	endfor
	execute 'noautocmd ' . cw . 'wincmd w'
endfunction

function! s:SpotDiffExpr()
	for n in ['in', 'new'] | let f_{n} = readfile(v:fname_{n}) | endfor
	" vim always tries to check with this dummy first call
	if f_in == ['line1'] && f_new == ['line2']
		call writefile(['1c1'], v:fname_out)
		return
	endif
	" leave only selected lines in 2 input files
	for sd in filter(map(range(1, winnr('$')),
						\'getwinvar(v:val, "SDiff", {})'), '!empty(v:val)')
		let sd{sd.id} = sd
		let n = (sd.id == 1) ? 'in' : 'new'
		call writefile(f_{n}[sd.range[0] - 1 : sd.range[1] - 1], v:fname_{n})
	endfor
	" execute original or custom diff
	if empty(s:save_dex)
		let opt = '-a --binary '
		if &diffopt =~ 'icase' | let opt .= '-i ' | endif
		if &diffopt =~ 'iwhite' | let opt .= '-b ' | endif
		let save_stmp = &shelltemp | let &shelltemp = 0
		let f_out = split(system('diff ' . opt . v:fname_in . ' ' .
														\v:fname_new), '\n')
		let &shelltemp = save_stmp
	else
		call eval(s:save_dex)
		let f_out = readfile(v:fname_out)
	endif
	" modify the line number of diff operations in output file
	for n in range(len(filter(f_out, 'v:val[0] !~ "[<>-]"')))
		let [se1, op, se2] = split(substitute(f_out[n], '[acd]', ' & ', ''))
		for k in [1, 2]
			let se{k} = substitute(se{k}, '\d\+',
								\'\= submatch(0) + sd{k}.range[0] - 1', 'g')
		endfor
		let f_out[n] = se1 . op . se2
	endfor
	call writefile(f_out, v:fname_out)
endfunction

function! s:RepairSpotDiff()
	" try to repair any diff mode mismatch in the current tab page
	for w in range(1, winnr('$'))
		let sd = getwinvar(w, 'SDiff', {})
		let df = getwinvar(w, '&diff')
		if !empty(sd) && !df
			" w has been Diffthis'ed but is not diff mode
			let do = 'diffthis'
		elseif empty(sd) && df
			" w has not been Diffthis'ed but is diff mode
			let do = 'diffoff'
		else
			continue
		endif
		" do repair
		let cw = winnr()
		execute 'noautocmd ' . w . 'wincmd w'
		execute 'silent ' . do
		execute 'noautocmd ' . cw . 'wincmd w'
	endfor
endfunction

function! s:ClearSpotDiff()
	" go to tabpage/window where BufWinLeave actually happend,
	" do Diffoff, return back to the current tabpage/window
	let [ct, cw] = [tabpagenr(), winnr()]
	for t in range(1, tabpagenr('$'))
		for w in range(1, tabpagewinnr(t, '$'))
			if winbufnr(w) == eval(expand('<abuf>'))
				execute 'noautocmd tabnext ' . t
				execute 'noautocmd ' . w . 'wincmd w'
				call spotdiff#Diffoff(0)
			endif
		endfor
	endfor
	execute 'noautocmd tabnext ' . ct
	execute 'noautocmd ' . cw . 'wincmd w'
	call s:ShowFoldSign()
endfunction

function! s:ToggleSpotDiff(on)
	for t in range(1, tabpagenr('$'))
		for w in range(1, tabpagewinnr(t, '$'))
			if !empty(gettabwinvar(t, w, 'SDiff', {}))
				" do nothing if a SDiff is still set in some window
				return
			endif
		endfor
	endfor
	" initialize event group
	augroup spotdiff
		autocmd!
	augroup END
	if a:on
		" set event
		autocmd spotdiff BufWinLeave * call s:ClearSpotDiff()
	else
		" remove event group
		augroup! spotdiff
	endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
