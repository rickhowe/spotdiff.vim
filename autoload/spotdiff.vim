" spotdiff.vim : A range and area selectable :diffthis to compare partially
"
" Last Change:	2021/06/08
" Version:		4.1
" Author:		Rick Howe <rdcxy754@ybb.ne.jp>
" Copyright:	(c) 2014-2021 by Rick Howe

let s:save_cpo = &cpoptions
set cpo&vim

" --------------------------------------
" A Range of Lines SpotDiff
" --------------------------------------
let s:RSD = 'r_spotdiff'

function! spotdiff#Diffthis(sl, el) abort
	if !exists('t:RSDiff') | let t:RSDiff = {}
	elseif 2 <= len(t:RSDiff)
		call s:EchoError('2 area already selected in this tab page!')
		return
	endif
	let cw = win_getid() | let cb = winbufnr(cw)
	let [k, j] = has_key(t:RSDiff, 1) ? [2, 1] : [1, 2]
	if empty(t:RSDiff) || t:RSDiff[j].bnr != cb
		" diffthis on the 1st or the 2nd different buffer
		let t:RSDiff[k] = {'wid': cw, 'bnr': cb, 'sel': [a:sl, a:el]}
	else
		" diffthis on the 2nd same buffer
		" save winfix options and set them in all non-RSDiff windows
		for w in gettabinfo(tabpagenr())[0].windows
			if w != t:RSDiff[j].wid
				let wf = {}
				for hw in ['winfixheight', 'winfixwidth']
					let wf[hw] = getwinvar(w, '&' . hw)
					call setwinvar(w, '&' . hw, 1)
				endfor
				call setwinvar(w, 'RSDiffWFX', wf)
			endif
		endfor
		let tx = getline(a:sl, a:el)
		let wo = getwinvar(cw, '&', {})
		let bo = getbufvar(cb, '&', {})
		" get height of a clone window, create it, and copy the selected text
		let lc = [line('.'), col('.')]
		call cursor([a:sl, 1]) | let ch = winline()
		call cursor([a:el, col([a:el, '$'])]) | let ch = winline() - ch + 1
		let ch = max([ch, a:el - a:sl + 1])
		call cursor(lc)
		let mh = (winheight(0) - 1) / 2
		if t:RSDiff[j].wid != cw
			" move to the original split window
			let cw = t:RSDiff[j].wid
			noautocmd call win_gotoid(t:RSDiff[j].wid)
		endif
		call execute(((t:RSDiff[j].sel[0] > a:sl) ? 'above ' : 'below ') .
													\min([ch, mh]) . 'new')
		call setline(1, tx)
		let t:RSDiff[k] = {'wid': win_getid(), 'bnr': bufnr('%'),
									\'sel': [1, a:el - a:sl + 1], 'cln': cw}
	endif
	call s:RS_ToggleSelHL(1, k)
	call s:RS_DoDiff(1)
	if has_key(t:RSDiff[k], 'cln')
		call map(wo, 'setwinvar(t:RSDiff[k].wid, "&" . v:key, v:val)')
		call map(bo, 'setbufvar(t:RSDiff[k].bnr, "&" . v:key, v:val)')
		" set some specific local options
		let &l:modifiable = 0
		let &l:buftype = 'nofile'
		let &l:bufhidden = 'wipe'
		let &l:buflisted = 0
		let &l:swapfile = 0
		" adjust height of clone window with foldclosed and diff filler lines
		let xh = 0 | let l = 1
		while l <= line('$') + 1
			let fe = foldclosedend(l)
			if fe != -1 | let xh -= fe - l | let l = fe
			else | let xh += diff_filler(l)
			endif
			let l += 1
		endwhile
		if xh != 0 | call execute('resize ' . min([ch + xh, mh])) | endif
	endif
	call s:RS_ToggleEvent(1)
endfunction

function! spotdiff#Diffoff(all) abort
	if !exists('t:RSDiff') | return | endif
	let cw = win_getid()
	let sk = keys(t:RSDiff)
	if !a:all
		call filter(sk, 't:RSDiff[v:val].wid == cw')
		if empty(sk) | return | endif
		if len(t:RSDiff) == 2 &&
							\has_key(t:RSDiff[(sk[0] == 1) ? 2 : 1], 'cln')
			let sk = [1, 2]
		endif
	endif
	for k in sk
		noautocmd call win_gotoid(t:RSDiff[k].wid)
		call s:RS_DoDiff(0)
		call s:RS_ToggleSelHL(0, k)
		if has_key(t:RSDiff[k], 'cln')
			if t:RSDiff[k].wid == cw | let cw = t:RSDiff[k].cln | endif
			let qw = win_id2win(t:RSDiff[k].wid)
		endif
		unlet t:RSDiff[k]
	endfor
	if empty(t:RSDiff) | unlet t:RSDiff | endif
	noautocmd call win_gotoid(cw)
	if a:all | call execute('diffoff!') | endif
	if exists('qw')
		" finally quit clone window and then restore winfix options
		call execute((exists('#diffchar#CursorHold') ?
										\'' : 'noautocmd ') . qw . 'quit!')
		for w in gettabinfo(tabpagenr())[0].windows
			let wv = getwinvar(w, '')
			if has_key(wv, 'RSDiffWFX')
				for [hw, vl] in items(wv.RSDiffWFX)
					call setwinvar(w, '&' . hw, vl)
				endfor
				unlet wv.RSDiffWFX
			endif
		endfor
	endif
	call s:RS_ToggleEvent(0)
endfunction

function! spotdiff#Diffupdate() abort
	if !exists('t:RSDiff') || len(t:RSDiff) != 2 | return | endif
	call execute('diffoff!')
	let cw = win_getid()
	for k in [1, 2]
		noautocmd call win_gotoid(t:RSDiff[k].wid)
		call execute('diffthis')
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! s:RS_DoDiff(on) abort
	call s:RS_ToggleDiffexpr(a:on)
	call execute(a:on ? 'diffthis' : 'diffoff')
endfunction

function! s:RS_ToggleDiffexpr(on)
	let rd = exists('t:RSDiff') && len(t:RSDiff) == 2
	if a:on == 1 && rd || a:on == -1 && rd
		if !exists('s:save_dex')
			let s:save_dex = &diffexpr
			let &diffexpr = '<SID>RS_Diffexpr()'
		endif
	elseif a:on == 0 && rd || a:on == -1 && !rd
		if exists('s:save_dex')
			let &diffexpr = s:save_dex
			unlet s:save_dex
		endif
	endif
endfunction

function! s:RS_Diffexpr() abort
	for n in ['in', 'new'] | let f_{n} = readfile(v:fname_{n}) | endfor
	if f_in == ['line1'] && f_new == ['line2']
		call writefile(['1c1'], v:fname_out)
		return
	endif
	for [k, n] in [[1, 'in'], [2, 'new']]
		let f_{n} = f_{n}[t:RSDiff[k].sel[0] - 1 : t:RSDiff[k].sel[1] - 1]
	endfor
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
	for ed in split(s:TraceDiffChar(f_in, f_new), '[+-]\+\zs', 1)[: -2]
		let [qe, q1, q2] = map(['=', '-', '+'], 's:CountChar(ed, v:val)')
		let [l1, l2] += [qe, qe]
		let f_out += [((1 < q1) ? l1 . ',' : '') . (l1 + q1 - 1) .
								\((q1 == 0) ? 'a' : (q2 == 0) ? 'd' : 'c') .
								\((1 < q2) ? l2 . ',' : '') . (l2 + q2 - 1)]
		let [l1, l2] += [q1, q2]
	endfor
	let &ignorecase = save_igc
	call filter(f_out, 'v:val[0] !~ "[<>-]"')
	for n in range(len(f_out))
		let [se1, op, se2] = split(substitute(f_out[n], '[acd]', ' & ', ''))
		for k in [1, 2]
			let se{k} = substitute(se{k}, '\d\+',
							\'\= submatch(0) + t:RSDiff[k].sel[0] - 1', 'g')
		endfor
		let f_out[n] = se1 . op . se2
	endfor
	call writefile(f_out, v:fname_out)
endfunction

function! s:RS_ClearDiff(wid) abort
	let cw = win_getid()
	noautocmd call win_gotoid(a:wid)
	call spotdiff#Diffoff(0)
	noautocmd call win_gotoid(cw)
endfunction

function! s:RS_ToggleEvent(on) abort
	let tv = filter(map(range(1, tabpagenr('$')),
							\'gettabvar(v:val, "RSDiff")'), '!empty(v:val)')
	if empty(tv)
		call execute(['augroup ' . s:RSD, 'autocmd!', 'augroup END',
														\'augroup! ' . s:RSD])
	else
		call execute(['augroup ' . s:RSD, 'autocmd!'])
		for tb in tv
			for k in keys(tb)
				call execute('autocmd ' .
					\(exists('##WinClosed') ? 'WinClosed' : 'BufWinLeave') .
						\' <buffer=' . tb[k].bnr . '> call s:RS_ClearDiff(' .
															\tb[k].wid . ')')
			endfor
		endfor
		call execute('autocmd! TabEnter * call s:RS_ToggleDiffexpr(-1)')
		call execute('augroup END')
	endif
endfunction

if has('signs')
	function! s:RS_ToggleSelHL(on, key) abort
		if a:on
			if s:Sign_placed() == 0 | call s:Sign_define() | endif
			if !has_key(t:RSDiff[a:key], 'scl')
				let t:RSDiff[a:key].scl = &l:signcolumn
				let &l:signcolumn = 'no'
			endif
			for l in range(t:RSDiff[a:key].sel[0], t:RSDiff[a:key].sel[-1])
				call s:Sign_place(t:RSDiff[a:key].bnr, l)
			endfor
		else
			for l in range(t:RSDiff[a:key].sel[0], t:RSDiff[a:key].sel[-1])
				call s:Sign_unplace(t:RSDiff[a:key].bnr, l)
			endfor
			if has_key(t:RSDiff[a:key], 'scl')
				let &l:signcolumn = t:RSDiff[a:key].scl
				unlet t:RSDiff[a:key].scl
			endif
			if s:Sign_placed() == 0 | call s:Sign_undefine() | endif
		endif
	endfunction

	if exists('*sign_define')
		function! s:Sign_define()
			call sign_define(s:RSD, {'linehl': 'CursorColumn',
									\'texthl': 'CursorColumn', 'text': '|'})
		endfunction
		function! s:Sign_undefine()
			call sign_undefine(s:RSD)
		endfunction
		function! s:Sign_place(bn, ln)
			call sign_place(a:ln, s:RSD, s:RSD, a:bn, {'lnum': a:ln})
		endfunction
		function! s:Sign_unplace(bn, ln)
			call sign_unplace(s:RSD, {'buffer': a:bn, 'id': a:ln})
		endfunction
		function! s:Sign_placed()
			let sn = 0
			for sb in sign_getplaced()
				let sn += len(sign_getplaced(sb.bufnr,
												\{'group': s:RSD})[0].signs)
			endfor
			return sn
		endfunction
	else
		function! s:Sign_define()
			call execute('sign define ' . s:RSD .
						\' linehl=CursorColumn texthl=CursorColumn text=|')
		endfunction
		function! s:Sign_undefine()
			call execute('sign undefine ' . s:RSD)
		endfunction
		function! s:Sign_place(bn, ln)
			call execute('sign place ' . (a:bn * 10000 + a:ln) .
					\' line=' . a:ln . ' name=' . s:RSD . ' buffer=' . a:bn)
		endfunction
		function! s:Sign_unplace(bn, ln)
			call execute('sign unplace ' . (a:bn * 10000 + a:ln) .
														\' buffer=' . a:bn)
		endfunction
		function! s:Sign_placed()
			return len(filter(split(execute('sign place'), '\n'),
														\'v:val =~ s:RSD'))
		endfunction
	endif
else
	function! s:RS_ToggleSelHL(on, key) abort
		if a:on
			let dc89 = !exists('g:loaded_diffchar') ||
									\type(g:loaded_diffchar) != type(0.0) ||
													\g:loaded_diffchar >= 8.9
			let t:RSDiff[a:key].lid = s:Matchaddpos('CursorColumn',
					\range(t:RSDiff[a:key].sel[0], t:RSDiff[a:key].sel[-1]),
								\dc89 ? -7 : max(t:RSDiff[a:key].sel) * -20,
														\t:RSDiff[a:key].wid)
		else
			call s:Matchdelete(t:RSDiff[a:key].lid, t:RSDiff[a:key].wid)
			unlet t:RSDiff[a:key].lid
		endif
	endfunction
endif

" --------------------------------------
" A Visual Area SpotDiff
" --------------------------------------

let s:VSD = 'v_spotdiff'

function! spotdiff#VDiffthis(sl, el, ll) abort
	if !exists('t:VSDiff') | let t:VSDiff = {}
	elseif 2 <= len(t:VSDiff)
		call s:EchoError('2 area already selected in this tab page!')
		return
	endif
	let cw = win_getid() | let cb = winbufnr(cw)
	" get selected start and end columns per line
	let vm = ([a:sl, a:el] == [line("'<"), line("'>")]) ? visualmode() : ''
	let tc = 0
	let se = []
	for ln in range(a:sl, a:el)
		let st = getbufline(cb, ln)[0]
		if empty(st)
			let [sc, ec] = [0, 0]
		"elseif empty(vm) || vm ==# 'V'
		elseif empty(vm)
			let [sc, ec] = [1, len(st)]
		else
			"if vm ==# 'v'
				"let [sc, ec] = [(ln == a:sl) ? col("'<") : 1,
										"\(ln == a:el) ? col("'>") : len(st)]
			"else
				let vp = '\%' . ln . 'l\%V.*\%V.'
				let so = 'cnw' . ((line('.') <= ln) ? '' : 'b')
				let [sc, ec] = map(['', 'e'], 'searchpos(vp, so . v:val)[1]')
			"endif
			if sc != 0 && ec != 0
				let ec += len(strcharpart(st[ec - 1 :], 0, 1)) - 1
			endif
		endif
		let se += [[ln, sc, ec]]
		if [sc, ec] != [0, 0] | let tc += 1 | endif
	endfor
	if tc == 0
		call s:EchoError('No text exists in this area!')
		return
	endif
	" check if the 2nd area is overwraped with the 1st one
	let [k, j] = has_key(t:VSDiff, 1) ? [2, 1] : [1, 2]
	if len(t:VSDiff) == 1 && t:VSDiff[j].wid == cw
		let lj = map(copy(t:VSDiff[j].sel), 'v:val[0]')
		for [ln, sc, ec] in se
			if [sc, ec] != [0, 0]
				let ix = index(lj, ln)
				if ix != -1
					if sc <= t:VSDiff[j].sel[ix][2] &&
												\t:VSDiff[j].sel[ix][1] <= ec
						call s:EchoError('A part of this area already
												\ selected in this window!')
						return
					endif
				endif
			endif
		endfor
	endif
	" do diffthis
	let t:VSDiff[k] =
					\{'wid': cw, 'bnr': cb, 'sel': se, 'vmd': vm, 'lbl': a:ll}
	call s:VS_ToggleSelHL(1, k)
	if len(t:VSDiff) == 2 | call s:VS_DoDiff() | endif
	call s:VS_ToggleMap(1)
	call s:VS_ToggleEvent(1)
endfunction

function! s:VS_DoDiff() abort
	" set diffopt flags for icase/iwhite
	let do = split(&diffopt, ',')
	let igc = (index(do, 'icase') != -1)
	let igw = (index(do, 'iwhiteall') != -1) ? 1 :
									\(index(do, 'iwhite') != -1) ? 2 :
									\(index(do, 'iwhiteeol') != -1) ? 3 : 0
	" set regular expression to split diff unit
	let du = get(t:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
	if du == 'Char'
		let sre = (igw == 1 || igw == 2) ? '\%(\s\+\|.\)\zs' : '\zs'
	elseif du == 'Word2'
		let sre = '\%(\s\+\|\S\+\)\zs'
	elseif du == 'Word3'
		let sre = '\<\|\>'
	else
		let sre = (igw == 1 || igw == 2) ?
								\'\%(\s\+\|\w\+\|\W\)\zs' : '\%(\w\+\|\W\)\zs'
	endif
	" set highlight colors for changed units
	let hcu = ['DiffText']
	let dc = get(t:, 'DiffColors', get(g:, 'DiffColors', 0))
	if 1 <= dc && dc <= 3
		let [fd, bd] = map(['fg#', 'bg#'], 'synIDattr(hlID("Normal"), v:val)')
		let id = 1
		while empty(fd) || empty(bd)
			let nm = synIDattr(id, 'name')
			if empty(nm) | break | endif
			if id == synIDtrans(id)
				if empty(fd) && synIDattr(id, 'bg') == 'fg'
					let fd = synIDattr(id, 'bg#')
				endif
				if empty(bd) && synIDattr(id, 'fg') == 'bg'
					let bd = synIDattr(id, 'fg#')
				endif
			endif
			let id += 1
		endwhile
		let xb = map(['DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText'],
											\'synIDattr(hlID(v:val), "bg#")')
		let hl = {}
		let id = 1
		while 1
			let nm = synIDattr(id, 'name')
			if empty(nm) | break | endif
			if id == synIDtrans(id)
				let [fg, bg, rv] = map(['fg#', 'bg#', 'reverse'],
													\'synIDattr(id, v:val)')
				if empty(fg) | let fg = fd | endif
				if !empty(rv) | let bg = !empty(fg) ? fg : fd | endif
				if !empty(bg) && bg != fg && bg != bd &&
													\index(xb, bg) == -1 &&
						\empty(filter(map(['bold', 'underline', 'undercurl',
									\'strikethrough', 'italic', 'standout'],
								\'synIDattr(id, v:val)'), '!empty(v:val)'))
					let hl[bg] = nm
				endif
			endif
			let id += 1
		endwhile
		let hcu += values(hl)[: ((dc == 1) ? 2 : (dc == 2) ? 6 : -1)]
	elseif dc == 100
		let dh = ['DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText']
		let hl = {}
		let id = 1
		while 1
			let nm = synIDattr(id, 'name')
			if empty(nm) | break | endif
			if id == synIDtrans(id) && index(dh, nm) == -1 &&
					\!empty(filter(['fg', 'bg', 'sp', 'bold', 'underline',
						\'undercurl', 'strikethrough', 'reverse', 'inverse',
													\'italic', 'standout'],
											'!empty(synIDattr(id, v:val))'))
				let hl[reltimestr(reltime())[-2 :] . id] = nm
			endif
			let id += 1
		endwhile
		let hcu += values(hl)
	elseif -3 <= dc && dc <= -1
		let hcu += ['SpecialKey', 'Search', 'CursorLineNr',
						\'Visual', 'WarningMsg', 'StatusLineNC', 'MoreMsg',
						\'ErrorMsg', 'LineNr', 'Conceal', 'NonText',
						\'ColorColumn', 'ModeMsg', 'PmenuSel', 'Title']
								\[: ((dc == -1) ? 2 : (dc == -2) ? 6 : -1)]
	endif
	" compare combined line or line-by-line
	let lm = (t:VSDiff[1].lbl && t:VSDiff[2].lbl) ?
					\min([t:VSDiff[1].sel[-1][0] - t:VSDiff[1].sel[0][0] + 1,
					\t:VSDiff[2].sel[-1][0] - t:VSDiff[2].sel[0][0] + 1]) : 1
	let hp = {1: {}, 2: {}}
	if get(t:, 'DiffPairVisible', get(g:, 'DiffPairVisible', 1))
		for k in [1, 2] | let t:VSDiff[k].pos = [] | endfor
	endif
	for ic in range(lm)
		let lct = {1: [], 2: []}
		for k in [1, 2]
			let lb = (&joinspaces && !t:VSDiff[k].lbl) ? nr2char(0xff) : ''
			" split line and set its position
			for [ln, sc, ec] in (t:VSDiff[k].lbl) ?
									\[t:VSDiff[k].sel[ic]] : t:VSDiff[k].sel
				let st = getbufline(t:VSDiff[k].bnr, ln)[0][sc - 1 : ec - 1]
				if empty(st)
					let lct[k] += [[[ln, 0, 0], '']]
				else
					for tx in split(st, sre)
						let tl = len(tx)
						let lct[k] += [[[ln, sc, tl], tx]]
						let sc += tl
					endfor
				endif
				" insert a linebreak between actual lines
				if !empty(lb) && ln < t:VSDiff[k].sel[-1][0]
					let lct[k] += [[[ln, sc, 1], lb]]
				endif
			endfor
			" delete linebreak if prev/next is splitable, or change to space
			if !empty(lb)
				for ix in filter(range(len(lct[k]) - 1, 0, -1),
													\'lct[k][v:val][1] == lb')
					let [pt, nt] = [lct[k][ix - 1][1], lct[k][ix + 1][1]]
					if empty(pt) || empty(nt) || 1 < len(split(pt . nt, sre))
						unlet lct[k][ix]
					else
						let lct[k][ix][1] = ' '
					endif
				endfor
			endif
			" adjust spaces based on iwhite
			if igw != 0
				for ix in range(len(lct[k]) - 1, 0, -1)
					if lct[k][ix][1] =~ '^\s\+$'
						unlet lct[k][ix]
					else
						if igw != 1 | break | endif
					endif
				endfor
			endif
			if igw == 2
				for ix in range(len(lct[k]))
					let lct[k][ix][1] =
								\substitute(lct[k][ix][1], '\s\+', ' ', 'g')
				endfor
			endif
		endfor
		" compare both diff units
		let sc = &ignorecase | let &ignorecase = igc
		let es = s:TraceDiffChar(map(copy(lct[1]), 'v:val[1]'),
											\map(copy(lct[2]), 'v:val[1]'))
		let &ignorecase = sc
		" set highlight positions
		let cn = 0 | let [p1, p2] = [0, 0]
		for ed in split(es, '[+-]\+\zs', 1)[: -2]
			let [qe, q1, q2] = map(['=', '-', '+'], 's:CountChar(ed, v:val)')
			if 0 < qe | let [p1, p2] += [qe, qe] | endif
			if 0 < q1 && 0 < q2
				let hl = hcu[cn % len(hcu)] | let cn += 1
			else
				let hl = 'DiffAdd'
			endif
			let [h1, h2] = [hl, hl]
			for k in [1, 2]
				let mx = []
				if 0 < q{k}		" add or change
					for ix in range(p{k}, p{k} + q{k} - 1)
						let mx += [lct[k][ix][0]]
					endfor
					let p{k} += q{k}
				else			" delete
					let h{k} = 'vsDiffChangeBU'
					if 0 < p{k}
						let po = lct[k][p{k} - 1][0]
						let bl = len(matchstr(lct[k][p{k} - 1][1], '.$'))
						let mx += [[po[0], po[1] + po[2] - bl, bl]]
					endif
					if p{k} < len(lct[k])
						let po = lct[k][p{k}][0]
						let bl = len(matchstr(lct[k][p{k}][1], '^.'))
						let mx += [[po[0], po[1], bl]]
					endif
				endif
				" join continueous positions per line and then per hl
				let lc = {}
				for [ln, sc, nc] in mx
					if !has_key(lc, ln)
						let lc[ln] = [sc, nc]
					else
						let lc[ln][1] = sc + nc - lc[ln][0]
					endif
				endfor
				let lx = map(items(lc), '[eval(v:val[0])] + v:val[1]')
				if !has_key(hp[k], h{k}) | let hp[k][h{k}] = [] | endif
				let hp[k][h{k}] += lx
				" set highlighted positions to show diff pair
				if get(t:, 'DiffPairVisible', get(g:, 'DiffPairVisible', 1))
					if 1 < len(lx)
						call sort(lx, {i, j -> i[0] - j[0]})
					endif
					let t:VSDiff[k].pos += [lx]
				endif
			endfor
		endfor
	endfor
	" draw diff highlights
	for k in [1, 2]
		let t:VSDiff[k].uid = []
		for [hl, po] in items(hp[k])
			let t:VSDiff[k].uid += s:Matchaddpos(hl, po, -3, t:VSDiff[k].wid)
		endfor
		if has('patch-8.0.1038') && t:VSDiff[k].lbl
			" strike uncompared extra lines for line-by-line
			let el = map(map(range(lm, len(t:VSDiff[k].sel) - 1, 1),
												\'t:VSDiff[k].sel[v:val]'),
							\'[v:val[0], v:val[1], v:val[2] - v:val[1] + 1]')
			if !empty(el)
				let t:VSDiff[k].uid +=
					\s:Matchaddpos('vsDiffChangeS', el, -3, t:VSDiff[k].wid)
			endif
		endif
	endfor
endfunction

function! spotdiff#VDiffoff(all, ...) abort
	if !exists('t:VSDiff') | return | endif
	let sk = keys(t:VSDiff)
	if !a:all
		call filter(sk, 't:VSDiff[v:val].wid == win_getid()')
		if 0 < a:0
			" select k within range (default: %) if both are in same window
			call filter(sk, 'a:1 <= t:VSDiff[v:val].sel[-1][0] &&
										\t:VSDiff[v:val].sel[0][0] <= a:2')
		endif
	endif
	if empty(sk) | return | endif
	call s:VS_ToggleMap(0)
	for k in sk
		call s:VS_ToggleSelHL(0, k)
		for id in ['uid', 'pid']
			if has_key(t:VSDiff[k], id)
				call s:Matchdelete(t:VSDiff[k][id], t:VSDiff[k].wid)
			endif
		endfor
		unlet t:VSDiff[k]
	endfor
	if len(t:VSDiff) == 1
		" resume back to the initial state
		let k = has_key(t:VSDiff, 1) ? 1 : 2
		for id in ['uid', 'pid']
			if has_key(t:VSDiff[k], id)
				call s:Matchdelete(t:VSDiff[k][id], t:VSDiff[k].wid)
				unlet t:VSDiff[k][id]
			endif
		endfor
		for id in ['pos', 'pvn']
			if has_key(t:VSDiff[k], id) | unlet t:VSDiff[k][id] | endif
		endfor
	elseif len(t:VSDiff) == 0
		unlet t:VSDiff
	endif
	call s:VS_ToggleEvent(0)
endfunction

function! spotdiff#VDiffupdate() abort
	if !exists('t:VSDiff') || len(t:VSDiff) != 2 | return | endif
	let vd = copy(t:VSDiff)
	call spotdiff#VDiffoff(1)
	let cw = win_getid()
	for k in [1, 2]
		noautocmd call win_gotoid(vd[k].wid)
		let [sl, sc] = [vd[k].sel[0][0], vd[k].sel[0][1]]
		let [el, ec] = [vd[k].sel[-1][0], vd[k].sel[-1][2]]
		if !empty(vd[k].vmd)
			call execute('normal ' . vd[k].vmd . "\<Esc>")
			call setpos("'<", [0, sl, sc, 0])
			call setpos("'>", [0, el, ec, 0])
		endif
		call spotdiff#VDiffthis(sl, el, vd[k].lbl)
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! spotdiff#VDiffOpFunc(vm, lbl) abort
	call execute('normal ' . ((a:vm == 'char') ? 'v' :
							\(a:vm == 'line') ? 'V' : "\<C-V>") . "\<Esc>")
	call setpos("'<", getpos("'["))
	call setpos("'>", getpos("']"))
	call spotdiff#VDiffthis(line("'<"), line("'>"), a:lbl)
endfunction

function! s:VS_ClearDiff(wid) abort
	let cw = win_getid()
	noautocmd call win_gotoid(a:wid)
	call spotdiff#VDiffoff(0)
	noautocmd call win_gotoid(cw)
endfunction

let s:vs_map =
	\{'<Plug>JumpDiffCharPrevStart': ':call <SID>VS_JumpDiff(0, 0)<CR>',
	\'<Plug>JumpDiffCharNextStart': ':call <SID>VS_JumpDiff(1, 0)<CR>',
	\'<Plug>JumpDiffCharPrevEnd': ':call <SID>VS_JumpDiff(0, 1)<CR>',
	\'<Plug>JumpDiffCharNextEnd': ':call <SID>VS_JumpDiff(1, 1)<CR>'}
call map(s:vs_map, '[maparg(v:key, "n"), v:val]')

function! s:VS_ToggleMap(on)
	let vd = exists('t:VSDiff') && len(t:VSDiff) == 2
	let rn = (a:on == 0 && vd || a:on == -1 && !vd) ? 0 :
							\(a:on == 1 && vd || a:on == -1 && vd) ? 1 : -1
	if rn != -1
		call execute(map(items(s:vs_map),
					\'"nnoremap <silent> " . v:val[0] . " " . v:val[1][rn]'))
	endif
endfunction

function! s:VS_JumpDiff(dir, pos) abort
	" a:dir : 0 = backward, 1 = forward / a:pos : 0 = start, 1 = end
	if !exists('t:VSDiff') || len(t:VSDiff) != 2 | return | endif
	let sk = filter(keys(t:VSDiff), 't:VSDiff[v:val].wid == win_getid()')
	if empty(sk) | return | endif
	let [cl, cc] = [line('.'), col('.')]
	if cc == col('$')		" empty line
		if !a:dir | let cc = 0 | endif
	else
		if a:pos
			let cc += len(strcharpart(getline(cl)[cc - 1 :], 0, 1)) - 1
		endif
	endif
	let ss = 0
	for k in sk
		for ix in a:dir ? range(len(t:VSDiff[k].sel)) :
									\range(len(t:VSDiff[k].sel) - 1, 0, -1)
			let sl = t:VSDiff[k].sel[ix]
			if a:dir ? (cl < sl[0] || cl == sl[0] && cc <= sl[2]) :
								\(cl > sl[0] || cl == sl[0] && cc >= sl[1])
				let s{k} = sl
				let ss += k
				break
			endif
		endfor
	endfor
	let sk = (ss == 0) ? [] : (ss == 1) ? [1] : (ss == 2) ? [2] :
				\(a:dir ? (s1[0] < s2[0] || s1[0] == s2[0] && s1[1] < s2[1]) :
						\(s1[0] > s2[0] || s1[0] == s2[0] && s1[1] > s2[1])) ?
															\[1, 2] : [2, 1]
	for k in sk
		for pn in a:dir ? (range(has_key(t:VSDiff[k], 'pvn') ?
									\t:VSDiff[k].pvn + (a:pos ? 0 : 1) : 0,
											\len(t:VSDiff[k].pos) - 1, 1)) :
										\(range(has_key(t:VSDiff[k], 'pvn') ?
										\t:VSDiff[k].pvn + (a:pos ? -1 : 0) :
											\len(t:VSDiff[k].pos) - 1, 0, -1))
			let ps = t:VSDiff[k].pos[pn][a:pos ? -1 : 0]
			let [nl, nc] = [ps[0], a:pos ? ps[1] + ps[2] - 1 : ps[1]]
			if a:dir ? (cl < nl || cl == nl && cc < nc) :
											\(cl > nl || cl == nl && cc > nc)
				call cursor(nl, nc)
				return
			endif
		endfor
	endfor
endfunction

function! s:VS_DiffPair(key, event) abort
	" a:event : 0 = WinLeave, 1 = CursorMoved
	if !exists('t:VSDiff') || len(t:VSDiff) != 2 | return | endif
	let [cl, cc] = [line('.'), col('.')]
	let bkey = (a:key == 1) ? 2 : 1
	if has_key(t:VSDiff[a:key], 'pvn')
		if a:event
			for ps in t:VSDiff[a:key].pos[t:VSDiff[a:key].pvn]
				if cl == ps[0] && ps[1] <= cc && cc <= ps[1] + ps[2] - 1
					return
				endif
			endfor
		endif
		unlet t:VSDiff[a:key].pvn
		call s:Matchdelete(t:VSDiff[bkey].pid, t:VSDiff[bkey].wid)
		unlet t:VSDiff[bkey].pid
	endif
	if a:event
		if t:VSDiff[a:key].sel[0][0] <= cl && cl <= t:VSDiff[a:key].sel[-1][0]
			let pn = len(t:VSDiff[a:key].pos) - 1
			while 0 <= pn
				for ps in t:VSDiff[a:key].pos[pn]
					if cl == ps[0] && ps[1] <= cc && cc <= ps[1] + ps[2] - 1
						let t:VSDiff[a:key].pvn = pn
						let t:VSDiff[bkey].pid =
								\s:Matchaddpos(has('nvim') ? 'TermCursor' :
								\has('gui_running') ? 'Cursor' : 'IncSearch',
							\t:VSDiff[bkey].pos[pn], -1, t:VSDiff[bkey].wid)
						let pn = 0
						break
					endif
				endfor
				let pn -= 1
			endwhile
		endif
	endif
endfunction

function! s:VS_ToggleEvent(on) abort
	let tv = filter(map(range(1, tabpagenr('$')),
							\'gettabvar(v:val, "VSDiff")'), '!empty(v:val)')
	if empty(tv)
		call execute(['augroup ' . s:VSD, 'autocmd!', 'augroup END',
														\'augroup! ' . s:VSD])
	else
		call execute(['augroup ' . s:VSD, 'autocmd!'])
		for tb in tv
			for k in keys(tb)
				call execute('autocmd ' .
					\(exists('##WinClosed') ? 'WinClosed' : 'BufWinLeave') .
						\' <buffer=' . tb[k].bnr . '> call s:VS_ClearDiff(' .
															\tb[k].wid . ')')
			endfor
			if len(tb) == 2 && get(t:, 'DiffPairVisible',
											\get(g:, 'DiffPairVisible', 1))
				for k in keys(tb)
					call execute('autocmd CursorMoved <buffer=' . tb[k].bnr .
										\'> call s:VS_DiffPair(' . k. ', 1)')
					call execute('autocmd WinLeave <buffer=' . tb[k].bnr .
										\'> call s:VS_DiffPair(' . k. ', 0)')
				endfor
			endif
		endfor
		call execute('autocmd TabEnter * call s:VS_ToggleMap(-1)')
		call execute('augroup END')
	endif
endfunction

function! s:VS_ToggleSelHL(on, key) abort
	let tv = filter(map(range(1, tabpagenr('$')),
							\'gettabvar(v:val, "VSDiff")'), '!empty(v:val)')
	if len(tv) == 1 && len(tv[0]) == 1 | call s:VS_ToggleHL(a:on) | endif
	if a:on
		let t:VSDiff[a:key].lid =
			\s:Matchaddpos(
						\t:VSDiff[a:key].lbl ? 'DiffChange' : 'vsDiffChangeI',
					\map(filter(copy(t:VSDiff[a:key].sel), 'v:val[1] != 0'),
						\'[v:val[0], v:val[1], v:val[2] - v:val[1] + 1]'), -5,
														\t:VSDiff[a:key].wid)
	else
		if has_key(t:VSDiff[a:key], 'lid')
			call s:Matchdelete(t:VSDiff[a:key].lid, t:VSDiff[a:key].wid)
			unlet t:VSDiff[a:key].lid
		endif
	endif
endfunction

function! s:VS_ToggleHL(on) abort
	for [fh, th, ta] in [['DiffChange', 'vsDiffChangeBU', 'bold,underline'],
							\['DiffChange', 'vsDiffChangeI', 'italic']] +
				\(has('patch-8.0.1038') ?
					\[['DiffChange', 'vsDiffChangeS', 'strikethrough']] : [])
		call execute('highlight clear ' . th)
		if a:on
			let at = {}
			let id = hlID(fh)
			for hm in ['term', 'cterm', 'gui']
				for hc in ['fg', 'bg', 'sp']
					let at[hm . hc] = synIDattr(id, hc, hm)
				endfor
				let at[hm] = join(filter(['bold', 'underline', 'undercurl',
							\'strikethrough', 'reverse', 'inverse', 'italic',
						\'standout'], 'synIDattr(id, v:val, hm) == 1'), ',')
				let at[hm] .= (!empty(at[hm]) ? ',' : '') . ta
			endfor
			call execute('highlight ' . th . ' ' .
								\join(map(items(filter(at, '!empty(v:val)')),
											\'v:val[0] . "=" . v:val[1]')))
		endif
	endfor
endfunction

" --------------------------------------
" Common
" --------------------------------------

function! s:TraceDiffChar(u1, u2) abort
	" An O(NP) Sequence Comparison Algorithm
	let [n1, n2] = [len(a:u1), len(a:u2)]
	if a:u1 == a:u2 | return repeat('=', n1)
	elseif n1 == 0 | return repeat('+', n2)
	elseif n2 == 0 | return repeat('-', n1)
	endif
	" reverse to be N >= M
	let [N, M, u1, u2, e1, e2] = (n1 >= n2) ?
			\[n1, n2, a:u1, a:u2, '+', '-'] : [n2, n1, a:u2, a:u1, '-', '+']
	let D = N - M
	let fp = repeat([-1], M + N + 1)
	let etree = []		" [next edit, previous p, previous k]
	let p = -1
	while fp[D] != N
		let p += 1
		let epk = repeat([[]], p * 2 + D + 1)
		for k in range(-p, D - 1, 1) + range(D + p, D, -1)
			let [y, epk[k]] = (fp[k - 1] < fp[k + 1]) ?
							\[fp[k + 1], [e1, (k < D) ? p - 1 : p, k + 1]] :
							\[fp[k - 1] + 1, [e2, (k > D) ? p - 1 : p, k - 1]]
			let x = y - k
			while x < M && y < N && u2[x] == u1[y]
				let epk[k][0] .= '='
				let [x, y] += [1, 1]
			endwhile
			let fp[k] = y
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

function! s:EchoError(msg) abort
	call execute(['echohl Error', 'echo a:msg', 'echohl None'], '')
endfunction

if has('patch-8.1.1084') || has('nvim-0.5.0')
	function! s:Matchaddpos(grp, pos, pri, wid) abort
		return map(range(0, len(a:pos) - 1, 8), 'matchaddpos(a:grp,
					\a:pos[v:val : v:val + 7], a:pri, -1, {"window": a:wid})')
	endfunction

	function! s:Matchdelete(id, wid) abort
		let gm = map(getmatches(a:wid), 'v:val.id')
		for id in a:id
			if index(gm, id) != -1 | call matchdelete(id, a:wid) | endif
		endfor
	endfunction
else
	function! s:Matchaddpos(grp, pos, pri, wid) abort
		let cw = win_getid()
		noautocmd call win_gotoid(a:wid)
		let id = map(range(0, len(a:pos) - 1, 8),
					\'matchaddpos(a:grp, a:pos[v:val : v:val + 7], a:pri)')
		noautocmd call win_gotoid(cw)
		return id
	endfunction

	function! s:Matchdelete(id, wid) abort
		let cw = win_getid()
		noautocmd call win_gotoid(a:wid)
		let gm = map(getmatches(), 'v:val.id')
		for id in a:id
			if index(gm, id) != -1 | call matchdelete(id) | endif
		endfor
		noautocmd call win_gotoid(cw)
	endfunction
endif

if has('patch-8.0.794')
	let s:CountChar = function('count')
else
	function! s:CountChar(str, chr) abort
		return len(a:str) - len(substitute(a:str, a:chr, '', 'g'))
	endfunction
endif

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
