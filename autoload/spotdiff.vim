" spotdiff.vim : A range selectable diffthis to compare partially
"
" Last Change:	2019/01/09
" Version:		3.1
" Author:		Rick Howe <rdcxy754@ybb.ne.jp>
" Copyright:	(c) 2014-2019 by Rick Howe

let s:save_cpo = &cpoptions
set cpo&vim

function! spotdiff#Diffthis(line1, line2, conceal)
	call s:RepairSpotDiff()
	let sw = filter(gettabinfo(tabpagenr())[0].windows,
									\'!empty(getwinvar(v:val, "SDiff", {}))')
	if 2 <= len(sw)
		echohl Error
		echo '2 windows have already been Diffthis''ed!'
		echohl None
		return
	endif
	call s:ToggleDiffexpr(1)
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
			if sw[0] != win_getid()
				echohl Error
				echo 'This buffer has already been Diffthis''ed on the
														\ different window!'
				echohl None
				return
			endif
			let [rg, cl] = [[1, a:line2 - a:line1 + 1] , 1]
			" get selected text and original local options
			let tx = getline(a:line1, a:line2)
			let wo = getwinvar(win_getid(), '&', {})
			let bo = getbufvar(bufnr('%'), '&', {})
			" locate cursor on the first line
			call cursor([sd.range[0], 1])
			" save winfix options and set them to 1
			for w in filter(gettabinfo(tabpagenr())[0].windows,
									\'empty(getwinvar(v:val, "SDiff", {}))')
				let wf = {}
				for hw in ['winfixheight', 'winfixwidth']
					let wf[hw] = getwinvar(w, '&' . hw)
					call setwinvar(w, '&' . hw, 1)
				endfor
				call setwinvar(w, 'SDiffWFX', wf)
			endfor
			" create a clone window and copy the selected text
			let mh = (winheight(0) - 1) / 2
			execute ((sd.range[0] > a:line1) ? 'above' : 'below') . ' 1new'
			call setline(1, tx)
		endif
	endif
	" set SDiff dictionary in this window
	let w:SDiff = {'id': id, 'range': rg, 'clone': cl}
	silent diffthis
	if w:SDiff.clone
		" copy original local options
		call map(wo, 'setwinvar(win_getid(), "&" . v:key, v:val)')
		call map(bo, 'setbufvar(bufnr("%"), "&" . v:key, v:val)')
		" set some specific local options
		let &l:foldmethod = 'diff'
		let &l:cursorbind = 0
		let &l:modifiable = 0
		let &l:buftype = 'nofile'
		let &l:bufhidden = 'wipe'
		let &l:buflisted = 0
		let &l:swapfile = 0
		" increase clone window height to fit all lines
		if line('$') == 1
			let ch = 1
			if foldclosedend(1) == -1 && &l:wrap
				if &cpoptions =~# 'n'
					let ch += ((virtcol([1, '$']) - 1) +
						\&l:numberwidth * (&l:relativenumber || &l:number)) /
												\(winwidth(0) - &l:foldcolumn)
				else
					let ch += (virtcol([1, '$']) - 1) /
											\(winwidth(0) - &l:foldcolumn -
						\&l:numberwidth * (&l:relativenumber || &l:number))
				endif
			endif
			execute 'resize ' . min([ch, mh])
		else
			let ch = 0
			let l = 1
			while l <= line('$')
				let ch += 1
				let fe = foldclosedend(l)
				if fe != -1 | let l = fe | endif
				let l += 1
			endwhile
			execute 'resize ' . min([ch, mh])
			while 1
				let xh = line('$') - (line('w$') - line('w0') + 1)
				if xh <= 0 | break | endif
				let ch += xh
				if ch < mh
					execute 'resize ' . ch
				else
					execute 'resize ' . mh
					break
				endif
			endwhile
		endif
		let xh = diff_filler(line('$') + 1)
		if 0 < xh
			let ch += xh
			execute 'resize ' . min([ch, mh])
		endif
	endif
	" place sign on selected lines
	if has('signs')
		redir => bs
		execute 'silent sign place buffer=' . bufnr('%')
		redir END
		if empty(filter(split(bs, '\n'), 'v:val =~ "=.*=.*="'))
			" if no sign exists in current buffer, hide signcolumn
			let w:SDiff.signcolumn = &l:signcolumn
			let &l:signcolumn = 'no'
		endif
		let base = win_getid() * bufnr('%') * 1000
		for n in range(w:SDiff.range[0], w:SDiff.range[1])
			execute 'silent sign place ' . (base + n) . ' line=' . n .
										\' name=SpotDiff buffer=' . bufnr('%')
		endfor
	endif
	" highlight other lines than selected with Conceal
	if a:conceal && has('conceal')
		let w:SDiff.conceal = matchadd('Conceal', '\%<' . w:SDiff.range[0] .
									\'l\|\%>' . w:SDiff.range[1] . 'l', -100)
	endif
	call s:ShowFoldSign()
endfunction

function! spotdiff#Diffoff(all)
	call s:RepairSpotDiff()
	let sw = filter(gettabinfo(tabpagenr())[0].windows,
									\'!empty(getwinvar(v:val, "SDiff", {}))')
	if empty(sw) | return | endif
	let cw = win_getid()
	if !a:all
		if index(sw, cw) == -1 | return | endif
		" if parent is diffoff'ed, clone is diffoff'ed together
		if len(sw) == 2
			let nw = sw[(sw[0] == cw) ? 1 : 0]
			if w:SDiff.clone || !getwinvar(nw, 'SDiff').clone
				let sw = [cw]
			endif
		endif
	endif
	for w in sw
		noautocmd call win_gotoid(w)
		silent diffoff
		" reset sign
		if has('signs')
			let base = win_getid() * winbufnr(w) * 1000
			for n in range(w:SDiff.range[0], w:SDiff.range[1])
				execute 'silent sign unplace ' . (base + n) .
													\' buffer=' . winbufnr(w)
			endfor
			let &l:signcolumn = w:SDiff.signcolumn
		endif
		" reset Conceal highlight
		if has_key(w:SDiff, 'conceal')
			if index(map(getmatches(), 'v:val.id'), w:SDiff.conceal) != -1
				call matchdelete(w:SDiff.conceal)
			endif
		endif
		if w:SDiff.clone
			" quit clone window, change current window, restore winfix options
			silent noautocmd quit!
			if exists('nw') && w == cw | let cw = nw | endif
			for w in gettabinfo(tabpagenr())[0].windows
				let wv = getwinvar(w, '')
				if has_key(wv, 'SDiffWFX')
					for [hw, vl] in items(wv.SDiffWFX)
						call setwinvar(w, '&' . hw, vl)
					endfor
					unlet wv.SDiffWFX
				endif
			endfor
		else
			unlet w:SDiff
		endif
	endfor
	noautocmd call win_gotoid(cw)
	if a:all | silent diffoff! | endif
	call s:ToggleSpotDiff(0)
	call s:ToggleDiffexpr(0)
	call s:ShowFoldSign()
endfunction

function! spotdiff#Diffupdate(reload)
	call s:RepairSpotDiff()
	execute 'silent diffupdate' . (a:reload ? '!' : '')
	call s:ShowFoldSign()
endfunction

function! s:ShowFoldSign()
	" show fold sign (-) at each selected lines on all sdiff windows
	let cw = win_getid()
	for sw in filter(gettabinfo(tabpagenr())[0].windows,
									\'!empty(getwinvar(v:val, "SDiff", {}))')
		noautocmd call win_gotoid(sw)
		let &l:foldmethod = 'diff'
		let &l:foldmethod = 'manual'
		for l in range(w:SDiff.range[0], w:SDiff.range[1])
			execute 'silent ' . l . 'fold'
			execute 'silent ' . l . 'foldopen'
		endfor
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! s:SpotDiffExpr()
	for n in ['in', 'new'] | let f_{n} = readfile(v:fname_{n}) | endfor
	" vim always tries to check with this dummy first call
	if f_in == ['line1'] && f_new == ['line2']
		call writefile(['1c1'], v:fname_out)
		return
	endif
	" leave only selected lines in 2 input files
	for sd in filter(map(gettabinfo(tabpagenr())[0].windows,
						\'getwinvar(v:val, "SDiff", {})'), '!empty(v:val)')
		let sd{sd.id} = sd
		let n = (sd.id == 1) ? 'in' : 'new'
		let f_{n} = f_{n}[sd.range[0] - 1 : sd.range[1] - 1]
	endfor
	if !empty(s:save_dex)
		" use custom diffexpr
		for n in ['in', 'new'] | call writefile(f_{n}, v:fname_{n}) | endfor
		call eval(s:save_dex)
		let f_out = readfile(v:fname_out)
	elseif executable('diff')
		" use external diff command
		for n in ['in', 'new'] | call writefile(f_{n}, v:fname_{n}) | endfor
		let opt = '-a --binary '
		let do = split(&diffopt, ',')
		if index(do, 'icase') != -1 | let opt .= '-i ' | endif
		if index(do, 'iwhiteall') != -1 | let opt .= '-w '
		elseif index(do, 'iwhite') != -1 | let opt .= '-b '
		elseif index(do, 'iwhiteeol') != -1 | let opt .= '-Z '
		endif
		let save_stmp = &shelltemp | let &shelltemp = 0
		let f_out = split(system('diff ' . opt . v:fname_in . ' ' .
														\v:fname_new), '\n')
		let &shelltemp = save_stmp
	else
		" use internal function
		let do = split(&diffopt, ',')
		let save_igc = &ignorecase
		let &ignorecase = (index(do, 'icase') != -1)
		if index(do, 'iwhiteall') != -1
			for n in ['in', 'new']
				call map(f_{n}, 'substitute(v:val, "\\s\\+", "", "g")')
			endfor
		elseif index(do, 'iwhite') != -1
			for n in ['in', 'new']
				call map(f_{n}, 'substitute(v:val, "\\s\\+", " ", "g")')
				call map(f_{n}, 'substitute(v:val, "\\s\\+$", "", "")')
			endfor
		elseif index(do, 'iwhiteeol') != -1
			for n in ['in', 'new']
				call map(f_{n}, 'substitute(v:val, "\\s\\+$", "", "")')
			endfor
		endif
		let f_out = []
		let [l1, l2] = [1, 1]
		for ed in split(s:TraceDiffChar(f_in, f_new), '\%(=\+\|[+-]\+\)\zs')
			let qn = len(ed)
			if ed[0] == '='		" one or more '='
				let [l1, l2] += [qn, qn]
			else				" one or more '[+-]'
				let q1 = len(substitute(ed, '+', '', 'g'))
				let q2 = qn - q1
				let f_out += [((1 < q1) ? l1 . ',' : '') . (l1 + q1 - 1) .
								\((q1 == 0) ? 'a' : (q2 == 0) ? 'd' : 'c') .
								\((1 < q2) ? l2 . ',' : '') . (l2 + q2 - 1)]
				let [l1, l2] += [q1, q2]
			endif
		endfor
		let &ignorecase = save_igc
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

function! s:TraceDiffChar(u1, u2)
	" An O(NP) Sequence Comparison Algorithm
	let [n1, n2] = [len(a:u1), len(a:u2)]
	if n1 == 0 && n2 == 0 | return ''
	elseif n1 == 0 | return repeat('+', n2)
	elseif n2 == 0 | return repeat('-', n1)
	endif
	" reverse to be M >= N
	let [M, N, u1, u2, e1, e2] = (n1 >= n2) ?
			\[n1, n2, a:u1, a:u2, '+', '-'] : [n2, n1, a:u2, a:u1, '-', '+']
	let D = M - N
	let fp = repeat([-1], M + N + 1)
	let etree = []		" [next edit, previous p, previous k]
	let p = -1
	while fp[D] != M
		let p += 1
		let epk = repeat([[]], p * 2 + D + 1)
		for k in range(-p, D - 1, 1) + range(D + p, D, -1)
			let [x, epk[k]] = (fp[k - 1] < fp[k + 1]) ?
							\[fp[k + 1], [e1, (k < D) ? p - 1 : p, k + 1]] :
							\[fp[k - 1] + 1, [e2, (k > D) ? p - 1 : p, k - 1]]
			let y = x - k
			while x < M && y < N && u1[x] == u2[y]
				let epk[k][0] .= '='
				let [x, y] += [1, 1]
			endwhile
			let fp[k] = x
		endfor
		let etree += [epk]
	endwhile
	" create a shortest edit script (SES) from last p and k
	let ses = ''
	while 1
		let ses = etree[p][k][0] . ses
		if p == 0 && k == 0 | return ses[1 :] | endif
		let [p, k] = etree[p][k][1 : 2]
	endwhile
endfunction

function! s:RepairSpotDiff()
	" try to repair any diff mode mismatch in the current tab page
	for w in gettabinfo(tabpagenr())[0].windows
		let sd = getwinvar(w, 'SDiff', {})
		let df = getwinvar(w, '&l:diff')
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
		let cw = win_getid()
		noautocmd call win_gotoid(w)
		execute 'silent ' . do
		noautocmd call win_gotoid(cw)
	endfor
endfunction

function! s:ClearSpotDiff()
	" go to tabpage/window where BufWinLeave actually happend,
	" do Diffoff, return back to the current tabpage/window
	let [ct, cw] = [tabpagenr(), win_getid()]
	for t in range(1, tabpagenr('$'))
		for w in gettabinfo(t)[0].windows
			if winbufnr(w) == eval(expand('<abuf>')) &&
									\!empty(gettabwinvar(t, w, 'SDiff', {}))
				execute 'noautocmd tabnext ' . t
				noautocmd call win_gotoid(w)
				call spotdiff#Diffoff(0)
			endif
		endfor
	endfor
	execute 'noautocmd tabnext ' . ct
	noautocmd call win_gotoid(cw)
	call s:ShowFoldSign()
endfunction

function! s:ToggleDiffexpr(on)
	let ns = empty(filter(gettabinfo(tabpagenr())[0].windows,
									\'!empty(getwinvar(v:val, "SDiff", {}))'))
	if a:on == 1 && ns || a:on == -1 && !ns
		if !exists('s:save_dex')
			" set a specific spotdiff expr to diffexpr
			let s:save_dex = &diffexpr
			let &diffexpr = 's:SpotDiffExpr()'
		endif
	elseif a:on == 0 && ns || a:on == -1 && ns
		if exists('s:save_dex')
			" restore original diffexpr
			let &diffexpr = s:save_dex
			unlet s:save_dex
		endif
	endif
endfunction

function! s:ToggleSpotDiff(on)
	if len(filter(getwininfo(), 'has_key(v:val.variables, "SDiff")')) > 0
		" do nothing if a SDiff is still set in some window
		return
	endif
	" initialize event group
	augroup spotdiff
		autocmd!
	augroup END
	if a:on
		" set event
		autocmd! spotdiff BufWinLeave,BufUnload * nested call s:ClearSpotDiff()
		autocmd! spotdiff TabEnter * call s:ToggleDiffexpr(-1)
		" define sign
		if has('signs')
			let at = 'underline'
			execute 'autocmd! spotdiff ColorScheme * silent hi sdSelectLine
								\ term=' . at . ' cterm=' .at . ' gui=' . at
			doautocmd spotdiff ColorScheme
			silent sign define SpotDiff linehl=sdSelectLine
		endif
	else
		" remove event group
		augroup! spotdiff
		" undefine sign
		if has('signs')
			silent hi clear sdSelectLine
			silent! sign undefine SpotDiff
		endif
	endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
