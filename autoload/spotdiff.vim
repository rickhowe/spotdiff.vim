" spotdiff.vim : A range selectable diffthis to compare any lines in buffers
"
" Last Change: 2017/01/26
" Version:     1.1
" Author:      Rick Howe <rdcxy754@ybb.ne.jp>

let s:save_cpo = &cpo
set cpo&vim

" define text and texthl for 2 signs
if !exists('g:SDiff_Sign')
	let g:SDiff_Sign = {'1': {'text': nr2char(0xA6), 'texthl': 'Search'},
			\'2': {'text': nr2char(0xA6), 'texthl': 'MatchParen'}}
endif

function! spotdiff#Diffthis(line1, line2)
	" try to repair any diff mode mismatch in the current tab page
	call s:RepairSpotDiff()

	" not allow more than 2 Diffthis buffers in a tab page
	let sb = filter(tabpagebuflist(), 'getbufvar(v:val, "SDiff_ID", 0)')
	if min(sb) != max(sb)
		echo "2 buffers have already been Diffthis'ed,
				\ use Diffoff[!] to reset either/all"
		return
	endif

	" set signs and events
	call s:ToggleSignEvents(1)

	if !exists('t:SDiff')
		" the first valid Diffthis
		let t:SDiff = {}
		let id = 1
		let rg = [a:line1 - 1, a:line2 - 1]
	else
		" the second valid Diffthis
		let id = has_key(t:SDiff, 1) ? 2 : 1

		if index(sb, bufnr('%')) == -1
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
			execute 'silent mkview ' . tn
			let &l:viewoptions = save_vop
			let op = join(filter(filter(readfile(tn),
					\'v:val =~ "^setlocal"'),
					\'v:val != "setlocal diff"'), '|')
			call delete(tn)

			" try to create a clone window
			try
				execute (t:SDiff[id == 1 ? 2 : 1][0] <
					\a:line1 ? 'below ' : 'above ') .
						\min([(winheight(0) - 1) / 2,
							\len(ln)]) . 'new'
			catch /^Vim(new):E36:/		" no room available
				echohl Error
				echo substitute(v:exception,
							\'^.\{-}:', '', '')
				echohl None
				return
			endtry

			" set the selected lines and original local options
			call setline(1, ln)
			execute op
			" set some specific local options
			let &l:modifiable = 0
			let &l:buftype = 'nofile'

			" set to identify a clone window
			let b:SDiff_Clone = 1
		endif
	endif
	let b:SDiff_ID = id
	let t:SDiff[id] = rg

	" set diffexpr to modify diff input/output files
	let s:save_dex = &diffexpr
	let &diffexpr = 's:DiffthisExpr()'
	" do diffthis
	silent diffthis
	" restore diffexpr
	let &diffexpr = s:save_dex
	unlet s:save_dex

	" place sign on selected lines
	for n in range(t:SDiff[id][0] + 1, t:SDiff[id][1] + 1)
		execute 'silent sign place ' . id . ' line=' . n .
			\' name=SDiff_' . id . ' buffer=' . bufnr('%')
	endfor
endfunction

function! spotdiff#Diffoff(all)
	" try to repair any diff mode mismatch in the current tab page
	call s:RepairSpotDiff()

	if !exists('t:SDiff') | return | endif

	let cwin = winnr()
	if a:all
		let sw = filter(range(winnr('$'), 1, -1),
				\'getbufvar(winbufnr(v:val), "SDiff_ID", 0)')
	elseif exists('b:SDiff_ID')
		let sw = filter(range(winnr('$'), 1, -1),
				\'winbufnr(v:val) == winbufnr(cwin)')
	else | return | endif

	for w in filter(sw, 'getwinvar(v:val, "&diff")')
		execute 'noautocmd ' . w . 'wincmd w'
		" reset sign and b: value
		if exists('b:SDiff_ID')
			unlet t:SDiff[b:SDiff_ID]
			unlet b:SDiff_ID
			execute 'silent sign unplace * buffer=' . winbufnr(w)
		endif
		" do diffoff
		silent diffoff
	endfor
	execute 'noautocmd ' . cwin . 'wincmd w'

	" do diffoff! if all
	if a:all | silent diffoff! | endif

	" reset t: value and option, sign, event
	if empty(t:SDiff)
		unlet t:SDiff
	endif
	call s:ToggleSignEvents(0)

	" quit all clone windows
	for w in filter(sw, 'getbufvar(winbufnr(v:val), "SDiff_Clone", 0)')
		execute 'noautocmd ' . w . 'wincmd w'
		silent quit!
		if cwin > w | let cwin -= 1
		elseif cwin == w | let cwin = winnr()
		endif
	endfor
	execute 'noautocmd ' . cwin . 'wincmd w'
endfunction

function! s:DiffthisExpr()
	let [f_in, f_new] = [readfile(v:fname_in), readfile(v:fname_new)]

	" vim always tries to check a dummy call first
	if f_in == ['line1'] && f_new == ['line2']
		call writefile(['1c1'], v:fname_out)
		return
	endif

	" leave only selected lines in 2 input files
	call writefile(f_in[t:SDiff[1][0] : t:SDiff[1][1]], v:fname_in)
	call writefile(f_new[t:SDiff[2][0] : t:SDiff[2][1]], v:fname_new)

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
					\'v:val + t:SDiff[id][0]'), ',')
		endfor
		let f_out += [se1 . op . se2]
	endfor
	call writefile(f_out, v:fname_out)
endfunction

function! s:RepairSpotDiff()
	let bw = {}
	for w in range(1, winnr('$'))
		let b = winbufnr(w)
		let bw[b] = get(bw, b, []) + [w]
	endfor

	for [b, wl] in items(bw)
		let id = getbufvar(eval(b), 'SDiff_ID', 0)
		let df = filter(copy(wl), 'getwinvar(v:val, "&diff")')
		if id && empty(df)
			" b has been Diffthis'ed but is not diff mode
			let do = 'diffthis'
		elseif !id && !empty(df)
			" b is diff mode but has not been Diffthis'ed
			let do = 'diffoff'
		else
			continue
		endif

		" do repair
		let cw = winnr()
		for w in wl
			execute 'noautocmd ' . w . 'wincmd w'
			execute 'silent ' . do
		endfor
		execute 'noautocmd ' . cw . 'wincmd w'
	endfor
endfunction

function! s:ClearSpotDiff()
	let abuf = eval(expand('<abuf>'))
	if abuf == bufnr('%')
		call spotdiff#Diffoff(0)
	else
		" find the tabpage/win where BufWinLeave actually happend,
		" go back there, do Diffoff, return to current tabpage/win
		let [ct, cw]  = [tabpagenr(), winnr()]
		for t in range(1, tabpagenr('$'))
			let bl = tabpagebuflist(t)
			for w in range(len(bl))
				if bl[w] == abuf
					execute 'noautocmd tabnext ' . t
					execute 'noautocmd ' . (w + 1) .
								\'wincmd w'
					call spotdiff#Diffoff(0)
				endif
			endfor
		endfor
		execute 'noautocmd tabnext ' . ct
		execute 'noautocmd ' . cw . 'wincmd w'
	endif
endfunction

function! s:ToggleSignEvents(on)
	if !empty(filter(range(1, tabpagenr('$')),
				\'!empty(gettabvar(v:val, "SDiff"))'))
		" do nothing if SDiff is still used in some tabpage
		return
	endif

	" initialize an event group
	augroup spotdiff
		autocmd!
	augroup END

	if a:on
		" define signs
		for id in [1, 2]
			execute 'silent sign define SDiff_' . id .
				\' text=' . g:SDiff_Sign[id].text .
				\' texthl=' . g:SDiff_Sign[id].texthl
		endfor
		" set events
		autocmd spotdiff BufWinLeave * call s:ClearSpotDiff()
	else
		" clear signs
		for id in [1, 2]
			execute 'silent sign undefine SDiff_' . id
		endfor
		" clear event group
		augroup! spotdiff
	endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
