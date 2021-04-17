" spotdiff.vim : A range and area selectable diffthis to compare partially
"
" Last Change:	2021/04/17
" Version:		4.0
" Author:		Rick Howe <rdcxy754@ybb.ne.jp>
" Copyright:	(c) 2014-2021 by Rick Howe

let s:save_cpo = &cpoptions
set cpo&vim

" --------------------------------------
" A Range of Lines SpotDiff
" --------------------------------------

function! spotdiff#Diffthis(sl, el) abort
	if !exists('t:RSDiff') | let t:RSDiff = {}
	elseif 2 <= len(t:RSDiff)
		call execute(['echohl Error', 'echo "2 area already selected
									\ in this tab page!"', 'echohl None'], '')
		return
	endif
	call s:RS_RepairDiff()
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
	call s:RS_ToggleSelHL(1, k)
endfunction

function! spotdiff#Diffoff(all) abort
	if !exists('t:RSDiff') | return | endif
	call s:RS_RepairDiff()
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
	call s:RS_ToggleEvent(0)
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
endfunction

function! spotdiff#Diffupdate(reload) abort
	if !exists('t:RSDiff') | return | endif
	call s:RS_RepairDiff()
	call execute('diffupdate' . (a:reload ? '!' : ''))
endfunction

function! spotdiff#Diffexpr() abort
	for n in ['in', 'new'] | let f_{n} = readfile(v:fname_{n}) | endfor
	if f_in == ['line1'] && f_new == ['line2']
		call writefile(['1c1'], v:fname_out)
		return
	endif
	for [k, n] in [[1, 'in'], [2, 'new']]
		let f_{n} = f_{n}[t:RSDiff[k].sel[0] - 1 : t:RSDiff[k].sel[1] - 1]
	endfor
	" use builtin function
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
	" modify the line number of diff operations in output file
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

function! s:RS_DoDiff(on) abort
	call s:RS_ToggleDiffexpr(a:on)
	call execute(a:on ? 'diffthis' : 'diffoff')
endfunction

function! s:RS_RepairDiff() abort
	" try to repair any diff mode mismatch in the current tab page
	let cw = win_getid()
	let sw = map(keys(t:RSDiff), 't:RSDiff[v:val].wid')
	for w in gettabinfo(tabpagenr())[0].windows
		let sd = [index(sw, w) != -1, getwinvar(w, '&l:diff')]
		let do = (sd == [1, 0]) ? 'diffthis' : (sd == [0, 1]) ? 'diffoff' : ''
		if !empty(do)
			noautocmd call win_gotoid(w)
			call execute(do)
		endif
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! s:RS_ClearDiff(wid) abort
	let cw = win_getid()
	noautocmd call win_gotoid(a:wid)
	call spotdiff#Diffoff(0)
	noautocmd call win_gotoid(cw)
endfunction

function! s:RS_ToggleEvent(on) abort
	let sd = 'r_spotdiff'
	let tv = filter(map(range(1, tabpagenr('$')),
							\'gettabvar(v:val, "RSDiff")'), '!empty(v:val)')
	call execute(['augroup ' . sd, 'autocmd!', 'augroup END'])
	let an = 0
	for tb in tv
		for k in keys(tb)
			call execute('autocmd! ' . sd . ' BufWinLeave <buffer=' .
					\tb[k].bnr . '> call s:RS_ClearDiff(' . tb[k].wid . ')')
			call execute('autocmd! ' . sd . ' TabEnter *
											\ call s:RS_ToggleDiffexpr(-1)')
			let an += 1
		endfor
	endfor
	if an == 0 | call execute('augroup! ' . sd) | endif
endfunction

function! s:RS_ToggleDiffexpr(on)
	let rd = exists('t:RSDiff') && len(t:RSDiff) == 2
	if a:on == 1 && rd || a:on == -1 && rd
		if !exists('s:save_dex')
			let s:save_dex = &diffexpr
			let &diffexpr = 'spotdiff#Diffexpr()'
		endif
	elseif a:on == 0 && rd || a:on == -1 && !rd
		if exists('s:save_dex')
			let &diffexpr = s:save_dex
			unlet s:save_dex
		endif
	endif
endfunction

function! s:RS_ToggleSelHL(on, k) abort
	if a:on
		let t:RSDiff[a:k].lid = s:Matchaddpos('CursorColumn',
						\range(t:RSDiff[a:k].sel[0], t:RSDiff[a:k].sel[-1]),
												\max(t:RSDiff[a:k].sel) * -20)
	else
		call s:Matchdelete(t:RSDiff[a:k].lid)
		unlet t:RSDiff[a:k].lid
	endif
endfunction

" --------------------------------------
" A Visual Area SpotDiff
" --------------------------------------

function! spotdiff#VDiffthis(sl, el, ll) abort
	if !exists('t:VSDiff') | let t:VSDiff = {}
	elseif 2 <= len(t:VSDiff)
		call execute(['echohl Error', 'echo "2 area already selected
									\ in this tab page!"', 'echohl None'], '')
		return
	endif
	let cw = win_getid() | let cb = winbufnr(cw)
	" get selected start/end lines and columns
	if type(a:sl) == type([])			" diffupdate
		let se = a:sl
	else
		let vm = ([a:sl, a:el] == [line("'<"), line("'>")])
		let se = []
		for ln in range(a:sl, a:el)
			let st = getbufline(cb, ln)[0]
			if empty(st)
				let [sc, ec] = [0, 0]
			else
				if vm
					let vp = '\%' . ln . 'l\%V.*\%V.'
					let so = 'cnw' . ((line('.') <= ln) ? '' : 'b')
					let [sc, ec] = map(['', 'e'],
											\'searchpos(vp, so . v:val)[1]')
					if sc != 0 && ec != 0
						let ec += len(strcharpart(st[ec - 1 :], 0, 1)) - 1
					endif
				else
					let [sc, ec] = [1, len(st)]
				endif
			endif
			let se += [[ln, sc, ec]]
		endfor
	endif
	" get line range and initialize the 1st or 2nd area
	let [k, j] = has_key(t:VSDiff, 1) ? [2, 1] : [1, 2]
	if len(t:VSDiff) == 1 && t:VSDiff[j].wid == cw
		let lj = map(copy(t:VSDiff[j].sel), 'v:val[0]')
		for [ln, sc, ec] in se
			if [sc, ec] != [0, 0]
				let ix = index(lj, ln)
				if ix != -1
					if sc <= t:VSDiff[j].sel[ix][2] &&
												\t:VSDiff[j].sel[ix][1] <= ec
						call execute(['echohl Error', 'echo "This area already
							\ selected in this window!"', 'echohl None'], '')
						return
					endif
				endif
			endif
		endfor
	endif
	let t:VSDiff[k] = {'wid': cw, 'bnr': cb, 'sel': se, 'lbl': a:ll}
	if len(t:VSDiff) == 2 | call s:VS_DoDiff() | endif
	call s:VS_ToggleEvent(1)
	call s:VS_ToggleSelHL(1, k)
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
				for [ln, sn] in items(lc)
					if !has_key(hp[k], h{k}) | let hp[k][h{k}] = [] | endif
					let hp[k][h{k}] += [[eval(ln)] + sn]
				endfor
			endfor
		endfor
	endfor
	" draw diff highlights
	let cw = win_getid()
	for k in [1, 2]
		noautocmd call win_gotoid(t:VSDiff[k].wid)
		let t:VSDiff[k].uid = []
		for [hl, po] in items(hp[k])
			let t:VSDiff[k].uid += s:Matchaddpos(hl, po, 0)
		endfor
		if has('patch-8.0.1038') && t:VSDiff[k].lbl
			" strike uncompared extra lines for line-by-line
			let el = map(map(range(lm, len(t:VSDiff[k].sel) - 1, 1),
												\'t:VSDiff[k].sel[v:val]'),
							\'[v:val[0], v:val[1], v:val[2] - v:val[1] + 1]')
			if !empty(el)
				let t:VSDiff[k].uid += s:Matchaddpos('vsDiffChangeS', el, 0)
			endif
		endif
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! spotdiff#VDiffoff(all, ...) abort
	if !exists('t:VSDiff') | return | endif
	let cw = win_getid()
	let sk = keys(t:VSDiff)
	if !a:all
		call filter(sk, 't:VSDiff[v:val].wid == cw')
		if 0 < a:0 && len(t:VSDiff) == 2
			" select k within range (default: %) if both are in same window
			call filter(sk, 'a:1 <= t:VSDiff[v:val].sel[-1][0] &&
										\t:VSDiff[v:val].sel[0][0] <= a:2')
		endif
	endif
	if empty(sk) | return | endif
	for k in sk
		noautocmd call win_gotoid(t:VSDiff[k].wid)
		call s:VS_ToggleSelHL(0, k)
		if has_key(t:VSDiff[k], 'uid')
			call s:Matchdelete(t:VSDiff[k].uid)
		endif
		unlet t:VSDiff[k]
	endfor
	if len(t:VSDiff) == 1
		" resume back to the initial state
		let k = has_key(t:VSDiff, 1) ? 1 : 2
		noautocmd call win_gotoid(t:VSDiff[k].wid)
		if has_key(t:VSDiff[k], 'uid')
			call s:Matchdelete(t:VSDiff[k].uid)
			unlet t:VSDiff[k].uid
		endif
	elseif len(t:VSDiff) == 0
		unlet t:VSDiff
	endif
	noautocmd call win_gotoid(cw)
	call s:VS_ToggleEvent(0)
endfunction

function! spotdiff#VDiffupdate() abort
	if !exists('t:VSDiff') || len(t:VSDiff) != 2 | return | endif
	let vd = copy(t:VSDiff)
	call spotdiff#VDiffoff(1)
	let cw = win_getid()
	for k in [1, 2]
		if has_key(vd, k)
			noautocmd call win_gotoid(vd[k].wid)
			call spotdiff#VDiffthis(vd[k].sel, 0, vd[k].lbl)
		endif
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! s:VS_ClearDiff(wid) abort
	let cw = win_getid()
	noautocmd call win_gotoid(a:wid)
	call spotdiff#VDiffoff(0)
	noautocmd call win_gotoid(cw)
endfunction

function! s:VS_ToggleEvent(on) abort
	let sd = 'v_spotdiff'
	let tv = filter(map(range(1, tabpagenr('$')),
							\'gettabvar(v:val, "VSDiff")'), '!empty(v:val)')
	call execute(['augroup ' . sd, 'autocmd!', 'augroup END'])
	let an = 0
	for tb in tv
		for k in keys(tb)
			call execute('autocmd ' . sd . ' BufWinLeave <buffer=' .
					\tb[k].bnr . '> call s:VS_ClearDiff(' . tb[k].wid . ')')
			let an += 1
		endfor
	endfor
	if an == 0 | call execute('augroup! ' . sd) | endif
	if an == 1 && a:on || an == 0 && !a:on | call s:VS_ToggleHL(a:on) | endif
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

function! s:VS_ToggleSelHL(on, k) abort
	if a:on
		let t:VSDiff[a:k].lid =
			\s:Matchaddpos(t:VSDiff[a:k].lbl ? 'DiffChange' : 'vsDiffChangeI',
						\map(filter(copy(t:VSDiff[a:k].sel), 'v:val[1] != 0'),
						\'[v:val[0], v:val[1], v:val[2] - v:val[1] + 1]'), -1)
	else
		if has_key(t:VSDiff[a:k], 'lid')
			call s:Matchdelete(t:VSDiff[a:k].lid)
			unlet t:VSDiff[a:k].lid
		endif
	endif
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

function! s:Matchaddpos(grp, pos, pri) abort
	return map(range(0, len(a:pos) - 1, 8),
					\'matchaddpos(a:grp, a:pos[v:val : v:val + 7], a:pri)')
endfunction

function! s:Matchdelete(id) abort
	let gm = map(getmatches(), 'v:val.id')
	for id in a:id
		if index(gm, id) != -1 | call matchdelete(id) | endif
	endfor
endfunction

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
