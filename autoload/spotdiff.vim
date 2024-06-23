" spotdiff.vim : A range and area selectable :diffthis to compare partially
"
" Last Change: 2024/06/23
" Version:     5.2
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2014-2024 by Rick Howe
" License:     MIT

let s:save_cpo = &cpoptions
set cpo&vim

" --------------------------------------
" A Range of Lines SpotDiff
" --------------------------------------
let s:RSD = 'r_spotdiff'

function! spotdiff#Diffthis(sl, el) abort
  let rn = !exists('t:RSDiff') ? 0 : len(t:RSDiff)
  if rn != len(filter(gettabinfo(tabpagenr())[0].windows,
                                                \'getwinvar(v:val, "&diff")'))
    call s:EchoWarning('More/less diff mode windows exist in this tabpage!')
    return
  elseif rn == 2
    call s:EchoWarning('2 pairs of range already selected in this tab page!')
    return
  endif
  let cw = win_getid() | let cb = winbufnr(cw)
  for tn in filter(range(1, tabpagenr('$')), 'v:val != tabpagenr()')
    let sd = gettabvar(tn, 'RSDiff')
    if !empty(sd) && index(map(values(sd), 'v:val.bnr'), cb) != -1
      call s:EchoWarning('This buffer already selected in tab page ' . tn .
                                                                        \'!')
      return
    endif
  endfor
  if rn == 0 | let t:RSDiff = {} | endif
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
    " get width or height of a clone window, create it, copy the selected text
    let vt = (&diffopt =~ 'vertical')
    if vt
      let mw = (winwidth(0) - 1) / 2
    else
      let mh = (winheight(0) - 1) / 2
      let lc = [line('.'), col('.')]
      call cursor([a:sl, 1]) | let ch = winline()
      call cursor([a:el, col([a:el, '$'])]) | let ch = winline() - ch + 1
      call cursor(lc)
      let ch = max([ch, a:el - a:sl + 1])
    endif
    if t:RSDiff[j].wid != cw
      " move to the original split window
      let cw = t:RSDiff[j].wid
      noautocmd call win_gotoid(t:RSDiff[j].wid)
    endif
    let ab = (vt && &splitright || !vt && &splitbelow ||
                    \t:RSDiff[j].sel[0] <= a:sl) ? 'belowright' : 'aboveleft'
    call execute(ab . ' ' . (vt ? mw . 'vnew' : min([ch, mh]) . 'new'))
    call setline(1, tx)
    let t:RSDiff[k] = {'wid': win_getid(), 'bnr': bufnr('%'),
                                      \'sel': [1, a:el - a:sl + 1], 'cln': cw}
  endif
  call s:RS_ToggleDiffexpr(1)
  call execute('diffthis')
  call s:RS_DrawClearSel(1, k)
  if has_key(t:RSDiff[k], 'cln')
    silent! call map(wo, 'setwinvar(t:RSDiff[k].wid, "&" . v:key, v:val)')
    silent! call map(bo, 'setbufvar(t:RSDiff[k].bnr, "&" . v:key, v:val)')
    " set some specific local options
    let &l:modifiable = 0
    let &l:buftype = 'nofile'
    let &l:bufhidden = 'wipe'
    let &l:buflisted = 0
    let &l:swapfile = 0
    if !vt
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
    if len(t:RSDiff) == 2 && has_key(t:RSDiff[(sk[0] == 1) ? 2 : 1], 'cln')
      let sk = [1, 2]
    endif
  endif
  for k in sk
    if win_id2win(t:RSDiff[k].wid) != 0
      noautocmd call win_gotoid(t:RSDiff[k].wid)
      call s:RS_DrawClearSel(0, k)
      call execute('diffoff')
      call s:RS_ToggleDiffexpr(0)
      if has_key(t:RSDiff[k], 'cln')
        let [cw, qw] = [t:RSDiff[k].wid == cw ? t:RSDiff[k].cln : cw,
                                                \win_id2win(t:RSDiff[k].wid)]
      endif
    else
      call s:RS_ToggleDiffexpr(0)
      if has_key(t:RSDiff[k], 'cln')
        let [cw, qw] = [t:RSDiff[k].cln, 0]
      else
        call s:RS_DrawClearSel(0, k)
      endif
    endif
    unlet t:RSDiff[k]
  endfor
  if empty(t:RSDiff) | unlet t:RSDiff | endif
  noautocmd call win_gotoid(cw)
  if a:all | call execute('diffoff!') | endif
  if exists('qw')
    " finally quit clone window and then restore winfix options
    if qw != 0
      call execute((exists('#diffchar#CursorHold') ? '' : 'noautocmd ') . qw .
                                                                    \'quit!')
    endif
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
  let rd = deepcopy(t:RSDiff)
  for k in [1, 2]
    if has_key(rd[k], 'cln') | call remove(t:RSDiff[k], 'cln') | endif
  endfor
  call spotdiff#Diffoff(1)
  let cw = win_getid()
  for k in [1, 2]
    noautocmd call win_gotoid(rd[k].wid)
    call spotdiff#Diffthis(rd[k].sel[0], rd[k].sel[-1])
    if has_key(rd[k], 'cln') | let t:RSDiff[k].cln = rd[k].cln | endif
  endfor
  noautocmd call win_gotoid(cw)
endfunction

function! s:RS_ToggleDiffexpr(on) abort
  let rd = exists('t:RSDiff') && len(t:RSDiff) == 2
  if a:on == 1 && rd || a:on == -1 && rd
    if !exists('s:save_dex')
      let s:save_dex = &diffexpr | let &diffexpr = 'spotdiff#Diffexpr()'
    endif
  elseif a:on == 0 && rd || a:on == -1 && !rd
    if exists('s:save_dex')
      let &diffexpr = s:save_dex | unlet s:save_dex
    endif
  endif
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
  let do = split(&diffopt, ',')
  for n in ['in', 'new']
    if index(do, 'icase') != -1
      call map(f_{n}, 'tolower(v:val)')
    endif
    if index(do, 'iwhiteall') != -1
      call map(f_{n}, 'substitute(v:val, "\\s\\+", "", "g")')
    elseif index(do, 'iwhite') != -1
      call map(f_{n}, 'substitute(v:val, "\\s\\+", " ", "g")')
      call map(f_{n}, 'substitute(v:val, "\\s\\+$", "", "")')
    elseif index(do, 'iwhiteeol') != -1
      call map(f_{n}, 'substitute(v:val, "\\s\\+$", "", "")')
    endif
  endfor
  let f_out = []
  let [l1, l2] = [1, 1]
  for ed in split(s:Diff(f_in, f_new,
                  \index(do, 'indent-heuristic') != -1), '[+-]\+\zs', 1)[: -2]
    let [qe, q1, q2] = map(['=', '-', '+'], 'count(ed, v:val)')
    let [l1, l2] += [qe, qe]
    let f_out += [((1 < q1) ? l1 . ',' : '') . (l1 + q1 - 1) .
                                  \((q1 == 0) ? 'a' : (q2 == 0) ? 'd' : 'c') .
                                  \((1 < q2) ? l2 . ',' : '') . (l2 + q2 - 1)]
    let [l1, l2] += [q1, q2]
  endfor
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

function! s:RS_ClearDiff(key) abort
  let cw = win_getid()
  noautocmd call win_gotoid(str2nr(expand('<amatch>')))
  call spotdiff#Diffoff(len(t:RSDiff) == 2 && &diffopt =~ 'closeoff')
  noautocmd call win_gotoid(cw)
endfunction

function! s:RS_RedrawDiff(key) abort
  " when text is changed, diffexpr is not called (why?) and then DiffUpdated
  " is not triggered, 'diffupdte' on TextChanged/InsertLeave instead
  call timer_start(0, {-> spotdiff#Diffupdate()})
endfunction

function! s:RS_ToggleEvent(on) abort
  let tv = filter(map(range(1, tabpagenr('$')),
                              \'gettabvar(v:val, "RSDiff")'), '!empty(v:val)')
  let ac = ['augroup ' . s:RSD, 'autocmd!']
  if !empty(tv)
    for tb in tv
      for k in keys(tb)
        let ac += ['autocmd WinClosed <buffer=' . tb[k].bnr .
                                          \'> call s:RS_ClearDiff(' . k . ')']
        if len(tb) == 2
          let ac += ['autocmd TextChanged,InsertLeave <buffer=' . tb[k].bnr .
                                        \'> call s:RS_RedrawDiff(' . k . ')']
        endif
      endfor
    endfor
    let ac += ['autocmd TabEnter * call s:RS_ToggleDiffexpr(-1)']
  endif
  let ac += ['augroup END']
  if empty(tv) | let ac += ['augroup! ' . s:RSD] | endif
  call execute(ac)
endfunction

function! s:RS_DrawClearSel(on, key) abort
  let rd = t:RSDiff[a:key]
  if a:on
    let hl = 'CursorColumn'
    let ss = substitute(get(t:, 'DiffRangeView',
                          \get(g:, 'DiffRangeView', 's')), '[^cfsv]', '', 'g')
    if ss =~ 's'
      if has('signs') &&
                      \empty(sign_getplaced(rd.bnr, {'group': '*'})[0].signs)
        let rd.scl = getwinvar(rd.wid, '&signcolumn')
        call setwinvar(rd.wid, '&signcolumn', 'no')
        if empty(sign_getdefined(s:RSD))
          call sign_define(s:RSD, {'linehl': hl})
        endif
        for ln in range(rd.sel[0], rd.sel[-1])
          call sign_place(0, s:RSD, s:RSD, rd.bnr, {'lnum': ln})
        endfor
      else
        let ss = substitute(ss, 's', '', 'g')
      endif
    endif
    if ss =~ 'v'
      let tx = '+'
      if has('textprop') && has('patch-9.0.0121')
        if empty(prop_type_get(s:RSD))
          call prop_type_add(s:RSD, {'highlight': hl})
        endif
        let rd.vtx = []
        for ln in range(rd.sel[0], rd.sel[-1])
          let rd.vtx += [prop_add(ln, 1, {'type': s:RSD, 'bufnr': rd.bnr,
                                                              \'text': tx})]
          let rd.vtx += [prop_add(ln, 0, {'type': s:RSD, 'bufnr': rd.bnr,
                                        \'text': tx, 'text_align': 'right'})]
        endfor
      elseif exists('*nvim_buf_set_extmark')
        let rd.vtx = {'ns': nvim_create_namespace(s:RSD), 'id': []}
        for ln in range(rd.sel[0], rd.sel[-1])
          let rd.vtx.id += [nvim_buf_set_extmark(rd.bnr, rd.vtx.ns, ln - 1, 0,
                        \{'virt_text': [[tx, hl]], 'virt_text_win_col': -99})]
          let rd.vtx.id += [nvim_buf_set_extmark(rd.bnr, rd.vtx.ns, ln - 1, 0,
                  \{'virt_text': [[tx, hl]], 'virt_text_pos': 'right_align'})]
        endfor
      else
        let ss = substitute(ss, 'v', '', 'g')
      endif
    endif
    if ss =~ 'c'
      if has('conceal')
        let rd.cid = s:Matchaddpos('Conceal', range(1, rd.sel[0] - 1) +
                              \range(rd.sel[-1] + 1, line('$')), -10, rd.wid)
      else
        let ss = substitute(ss, 'c', '', 'g')
      endif
    endif
    if ss =~ 'f'
      if has('folding')
        let rd.fdm = getwinvar(rd.wid, '&foldmethod')
        call setwinvar(rd.wid, '&foldmethod', 'manual')
        call execute(['normal zE'] +
                \((1 < rd.sel[0]) ? ['1,' . (rd.sel[0] - 1) . 'fold'] : []) +
            \((rd.sel[-1] < line('$')) ? [(rd.sel[-1] + 1) . ',$fold'] : []))
      else
        let ss = substitute(ss, 'f', '', 'g')
      endif
    endif
    if empty(ss)
      let dc89 = !exists('g:loaded_diffchar') ||
            \type(g:loaded_diffchar) != type(0.0) || g:loaded_diffchar >= 8.9
      let rd.lid = s:Matchaddpos(hl, range(rd.sel[0], rd.sel[-1]),
                                      \dc89 ? -10 : max(rd.sel) * -20, rd.wid)
    endif
  else
    if has_key(rd, 'scl')
      call sign_unplace(s:RSD, {'buffer': rd.bnr})
      if empty(filter(range(1, bufnr('$')), 'bufnr(v:val) != -1 &&
                  \!empty(sign_getplaced(v:val, {"group": s:RSD})[0].signs)'))
        call sign_undefine(s:RSD)
      endif
      call setwinvar(rd.wid, '&signcolumn', rd.scl)
      unlet rd.scl
    endif
    if has_key(rd, 'vtx')
      if has('textprop')
        for id in rd.vtx
          call prop_remove({'type': s:RSD, 'id': id, 'both': 1,
                                                  \'bufnr': rd.bnr, 'all': 1})
        endfor
        if empty(filter(range(1, bufnr('$')), 'bufnr(v:val) != -1 &&
            \!empty(prop_find({"type": s:RSD, "bufnr": v:val, "lnum": 1}))'))
          call prop_type_delete(s:RSD)
        endif
      else
        for id in rd.vtx.id
          call nvim_buf_del_extmark(rd.bnr, rd.vtx.ns, id)
        endfor
      endif
      unlet rd.vtx
    endif
    if has_key(rd, 'cid')
      call s:Matchdelete(rd.cid, rd.wid) | unlet rd.cid
    endif
    if has_key(rd, 'fdm')
      call execute('normal zE')
      call setwinvar(rd.wid, '&foldmethod', rd.fdm) | unlet rd.fdm
    endif
    if has_key(rd, 'lid')
      call s:Matchdelete(rd.lid, rd.wid) | unlet rd.lid
    endif
  endif
endfunction

" --------------------------------------
" A Visual Area SpotDiff
" --------------------------------------
let s:VSD = 'v_spotdiff'

function! spotdiff#VDiffthis(sl, el, ll) abort
  if !exists('t:VSDiff') | let t:VSDiff = {}
  elseif 2 <= len(t:VSDiff)
    call s:EchoWarning('2 area already selected in this tab page!')
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
    call s:EchoWarning('No text exists in this area!')
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
          if sc <= t:VSDiff[j].sel[ix][2] && t:VSDiff[j].sel[ix][1] <= ec
            call s:EchoWarning('A part of this area already selected in this
                                                                  \ window!')
            return
          endif
        endif
      endif
    endfor
  endif
  " do diffthis
  let t:VSDiff[k] = {'wid': cw, 'bnr': cb, 'sel': se, 'vmd': vm, 'lbl': a:ll}
  call s:VS_DrawClearSel(1, k)
  if len(t:VSDiff) == 2 | call s:VS_DoDiff() | endif
  call s:VS_ToggleMap(1)
  call s:VS_ToggleEvent(1)
endfunction

function! s:VS_DoDiff() abort
  " set diffopt flags for icase/iwhite/indent
  let do = split(&diffopt, ',')
  let igc = (index(do, 'icase') != -1)
  let igw = (index(do, 'iwhiteall') != -1) ? 1 :
                                      \(index(do, 'iwhite') != -1) ? 2 :
                                      \(index(do, 'iwhiteeol') != -1) ? 3 : 0
  let idh = (index(do, 'indent-heuristic') != -1)
  " set regular expression to split diff unit
  let du = get(t:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
  if du == 'Char'
    let sre = (igw == 1 || igw == 2) ? '\%(\s\+\|.\)\zs' : '\zs'
  elseif du == 'Word2' || du ==# 'WORD'
    let sre = '\%(\s\+\|\S\+\)\zs'
  elseif du == 'Word3' || du ==# 'word'
    let sre = '\<\|\>'
  elseif du =~ '^\[.\+\]$'
    let s = escape(du[1 : -2], ']^-\')
    let sre = '\%([^' . s . ']\+\|[' . s . ']\)\zs'
  elseif du =~ '^\([/?]\).\+\1$'
    let sre = du[1 : -2]
  else
    let sre = (igw == 1 || igw == 2) ? '\%(\s\+\|\w\+\|\W\)\zs' :
                                                          \'\%(\w\+\|\W\)\zs'
  endif
  " set highlight colors for changed units
  let vhl = ['DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText', 'Normal',
    \has('nvim') ? 'TermCursor' : has('gui_running') ? 'Cursor' : 'IncSearch']
  let hcu = ['DiffText']
  let dc = get(t:, 'DiffColors', get(g:, 'DiffColors', 0))
  if type(dc) == type([])
    let hcu += filter(copy(dc),
                  \'0 < hlID(v:val) && !empty(synIDattr(hlID(v:val), "bg#"))')
    if 1 < len(hcu) | unlet hcu[0] | endif
  elseif 1 <= dc && dc <= 3
    let lv = dc - 1
    let bx = []
    for nm in vhl
      let [fc, bc] = map(['fg#', 'bg#'],
                              \'s:ColorClass(synIDattr(hlID(nm), v:val), lv)')
      if !empty(bc) | let bx += [bc] | endif
      if nm == 'Normal' | let fn = fc | endif
    endfor
    let hl = {} | let id = 1
    while 1
      let nm = synIDattr(id, 'name')
      if empty(nm) | break | endif
      if id == synIDtrans(id) && empty(filter(['underline', 'undercurl',
                          \'strikethrough', 'reverse', 'inverse', 'standout'],
                                            \'!empty(synIDattr(id, v:val))'))
        let [fc, bc] = map(['fg#', 'bg#'],
                                    \'s:ColorClass(synIDattr(id, v:val), lv)')
        if !empty(bc) && index(bx + [!empty(fc) ? fc : fn], bc) == -1
          let wt = !empty(fc) + (!empty(filter(['bold', 'italic'],
                                        \'!empty(synIDattr(id, v:val))'))) * 2
          if !has_key(hl, bc) || hl[bc][0] < wt
            let hl[bc] = [wt, nm]
          endif
        endif
      endif
      let id += 1
    endwhile
    let hcu += map(values(hl), 'v:val[1]')
  elseif dc == 100
    let bx = map(vhl, 'synIDattr(hlID(v:val), "bg#")')
    let hl = {} | let id = 1
    while 1
      let nm = synIDattr(id, 'name')
      if empty(nm) | break | endif
      if id == synIDtrans(id)
        let bg = synIDattr(id, 'bg#')
        if !empty(bg) && index(bx, bg) == -1
          let hl[reltimestr(reltime())[-2 :] . id] = nm
          let bx += [bg]
        endif
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
  for k in [1, 2] | let t:VSDiff[k].pos = [] | endfor
  for ic in range(lm)
    let lct = {1: [], 2: []}
    for k in [1, 2]
      let lb = (&joinspaces && !t:VSDiff[k].lbl) ? nr2char(0xff) : ''
      " split line and set its position
      for [ln, sc, ec] in (t:VSDiff[k].lbl) ? [t:VSDiff[k].sel[ic]] :
                                                              \t:VSDiff[k].sel
        let st = getbufline(t:VSDiff[k].bnr, ln)[0][sc - 1 : ec - 1]
        if empty(st)
          let lct[k] += [[[ln, 0, 0], '']]
        else
          if igc | let st = tolower(st) | endif
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
          let lct[k][ix][1] = substitute(lct[k][ix][1], '\s\+', ' ', 'g')
        endfor
      endif
    endfor
    " compare both diff units
    let es = s:Diff(map(copy(lct[1]), 'v:val[1]'),
                                          \map(copy(lct[2]), 'v:val[1]'), idh)
    " set highlight positions
    let cn = 0 | let [p1, p2] = [0, 0]
    for ed in split(es, '[+-]\+\zs', 1)[: -2]
      let [qe, q1, q2] = map(['=', '-', '+'], 'count(ed, v:val)')
      if 0 < qe | let [p1, p2] += [qe, qe] | endif
      if 0 < q1 && 0 < q2
        let hl = hcu[cn % len(hcu)] | let cn += 1
      else
        let hl = 'DiffAdd'
      endif
      let [h1, h2] = [hl, hl]
      for k in [1, 2]
        let mx = []
        if 0 < q{k}   " add or change
          for ix in range(p{k}, p{k} + q{k} - 1)
            let mx += [lct[k][ix][0]]
          endfor
          let p{k} += q{k}
        else          " delete
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
        if 1 < len(lx) | call sort(lx, {i, j -> i[0] - j[0]}) | endif
        let t:VSDiff[k].pos += [lx]
      endfor
    endfor
  endfor
  " draw diff highlights
  for k in [1, 2]
    let t:VSDiff[k].uid = []
    for [hl, po] in items(hp[k])
        let t:VSDiff[k].uid += s:Matchaddpos(hl, po, -3, t:VSDiff[k].wid)
    endfor
    if t:VSDiff[k].lbl
      " strike uncompared extra lines for line-by-line
      let el = map(map(range(lm, len(t:VSDiff[k].sel) - 1, 1),
                                                  \'t:VSDiff[k].sel[v:val]'),
                            \'[v:val[0], v:val[1], v:val[2] - v:val[1] + 1]')
      if !empty(el)
        let t:VSDiff[k].uid += s:Matchaddpos('vsDiffChangeS', el, -3,
                                                            \t:VSDiff[k].wid)
      endif
    endif
  endfor
endfunction

function! spotdiff#VDiffoff(all) abort
  if !exists('t:VSDiff') | return | endif
  let sk = keys(t:VSDiff)
  if !a:all
    call filter(sk, 't:VSDiff[v:val].wid == win_getid()')
    if len(sk) == 2
      " select k in which the cursor is if both are in same window
      let [cl, cc] = [line('.'), col('.')]
      for k in sk
        if !empty(filter(copy(t:VSDiff[k].sel), 'v:val[0] == cl &&
                                          \v:val[1] <= cc && cc <= v:val[2]'))
          let sk = [k]
          break
        endif
      endfor
    endif
  endif
  if empty(sk) | return | endif
  call s:VS_ToggleMap(0)
  for k in sk
    call s:VS_DrawClearSel(0, k)
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
  call execute('normal ' . ((a:vm == 'char') ? 'v' : (a:vm == 'line') ? 'V' :
                                                        \"\<C-V>") . "\<Esc>")
  call setpos("'<", getpos("'["))
  call setpos("'>", getpos("']"))
  call spotdiff#VDiffthis(line("'<"), line("'>"), a:lbl)
endfunction

function! s:VS_ClearDiff(key) abort
  let cw = win_getid()
  noautocmd call win_gotoid(str2nr(expand('<amatch>')))
  call spotdiff#VDiffoff(0)
  noautocmd call win_gotoid(cw)
endfunction

function! s:VS_RedrawDiff(key) abort
  call spotdiff#VDiffupdate()
endfunction

if exists('g:loaded_diffchar')
  let s:vs_map =
    \{'<Plug>JumpDiffCharPrevStart': ':call <SID>VS_JumpDiff(0, 0)<CR>',
    \'<Plug>JumpDiffCharNextStart': ':call <SID>VS_JumpDiff(1, 0)<CR>',
    \'<Plug>JumpDiffCharPrevEnd': ':call <SID>VS_JumpDiff(0, 1)<CR>',
    \'<Plug>JumpDiffCharNextEnd': ':call <SID>VS_JumpDiff(1, 1)<CR>'}
  call map(s:vs_map, '[maparg(v:key, "n"), v:val]')
  function! s:VS_ToggleMap(on) abort
    let vd = exists('t:VSDiff') && len(t:VSDiff) == 2
    let rn = (a:on == 0 && vd || a:on == -1 && !vd) ? 0 :
                              \(a:on == 1 && vd || a:on == -1 && vd) ? 1 : -1
    if rn != -1
      call execute(map(items(s:vs_map),
                    \'"nnoremap <silent> " . v:val[0] . " " . v:val[1][rn]'))
    endif
  endfunction
else
  for [key, plg, cmd] in [
    \['[b', '<Plug>JumpDiffCharPrevStart', ':call <SID>VS_JumpDiff(0, 0)'],
    \[']b', '<Plug>JumpDiffCharNextStart', ':call <SID>VS_JumpDiff(1, 0)'],
    \['[e', '<Plug>JumpDiffCharPrevEnd', ':call <SID>VS_JumpDiff(0, 1)'],
    \[']e', '<Plug>JumpDiffCharNextEnd', ':call <SID>VS_JumpDiff(1, 1)']]
    if !hasmapto(plg, 'n') && empty(maparg(key, 'n'))
      if get(g:, 'DiffCharDoMapping', 1) && get(g:, 'VDiffDoMapping', 1)
        call execute('nmap <silent> ' . key . ' ' . plg)
      endif
    endif
    call execute('nnoremap <silent> ' . plg . ' ' . cmd . '<CR>')
  endfor
  function! s:VS_ToggleMap(on) abort
  endfunction
endif

function! s:VS_JumpDiff(dir, pos) abort
  " a:dir : 0 = backward, 1 = forward / a:pos : 0 = start, 1 = end
  if !exists('t:VSDiff') || len(t:VSDiff) != 2 | return | endif
  let sk = filter(keys(t:VSDiff), 't:VSDiff[v:val].wid == win_getid()')
  if empty(sk) | return | endif
  let [cl, cc] = [line('.'), col('.')]
  if cc == col('$')     " empty line
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
        \(s1[0] > s2[0] || s1[0] == s2[0] && s1[1] > s2[1])) ? [1, 2] : [2, 1]
  for k in sk
    for pn in a:dir ? (range(has_key(t:VSDiff[k], 'pvn') ?
      \t:VSDiff[k].pvn + (a:pos ? 0 : 1) : 0, len(t:VSDiff[k].pos) - 1, 1)) :
                      \(range(has_key(t:VSDiff[k], 'pvn') ?
      \t:VSDiff[k].pvn + (a:pos ? -1 : 0) : len(t:VSDiff[k].pos) - 1, 0, -1))
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
            let t:VSDiff[bkey].pid = s:Matchaddpos(has('nvim') ?
                  \'TermCursor' : has('gui_running') ? 'Cursor' : 'IncSearch',
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
  let ac = ['augroup ' . s:VSD, 'autocmd!']
  if !empty(tv)
    for tb in tv
      for k in keys(tb)
        let ac += ['autocmd WinClosed <buffer=' . tb[k].bnr .
                                          \'> call s:VS_ClearDiff(' . k . ')']
        if len(tb) == 2
          let ac += ['autocmd TextChanged,InsertLeave <buffer=' . tb[k].bnr .
                                        \'> call s:VS_RedrawDiff(' . k . ')']
          if get(t:, 'DiffPairVisible', get(g:, 'DiffPairVisible', 1))
            let ac += ['autocmd CursorMoved <buffer=' . tb[k].bnr .
                                        \'> call s:VS_DiffPair(' . k . ', 1)']
            let ac += ['autocmd WinLeave <buffer=' . tb[k].bnr .
                                        \'> call s:VS_DiffPair(' . k . ', 0)']
          endif
        endif
      endfor
    endfor
    let ac += ['autocmd ColorScheme * call s:VS_ToggleHL(1)']
    let ac += ['autocmd TabEnter * call s:VS_ToggleMap(-1)']
  endif
  let ac += ['augroup END']
  if empty(tv) | let ac += ['augroup! ' . s:VSD] | endif
  call execute(ac)
endfunction

function! s:VS_DrawClearSel(on, key) abort
  let tv = filter(map(range(1, tabpagenr('$')),
                              \'gettabvar(v:val, "VSDiff")'), '!empty(v:val)')
  if len(tv) == 1 && len(tv[0]) == 1 | call s:VS_ToggleHL(a:on) | endif
  if a:on
    let t:VSDiff[a:key].lid =
          \s:Matchaddpos(t:VSDiff[a:key].lbl ? 'DiffChange' : 'vsDiffChangeI',
                      \map(filter(copy(t:VSDiff[a:key].sel), 'v:val[1] != 0'),
                            \'[v:val[0], v:val[1], v:val[2] - v:val[1] + 1]'),
                                                    \-5, t:VSDiff[a:key].wid)
  else
    if has_key(t:VSDiff[a:key], 'lid')
      call s:Matchdelete(t:VSDiff[a:key].lid, t:VSDiff[a:key].wid)
      unlet t:VSDiff[a:key].lid
    endif
  endif
endfunction

function! s:VS_ToggleHL(on) abort
  for [fh, th, ta] in [
                    \['DiffChange', 'vsDiffChangeBU', ['bold', 'underline']],
                    \['DiffChange', 'vsDiffChangeI', ['italic']],
                    \['DiffChange', 'vsDiffChangeS', ['strikethrough']]]
    call execute('highlight clear ' . th)
    if a:on
      let at = {}
      let id = synIDtrans(hlID(fh))
      for hm in ['cterm', 'gui']
        for hc in ['fg', 'bg']
          let at[hm . hc] = synIDattr(id, hc, hm)
        endfor
        let at[hm] = join(filter(['bold', 'underline', 'undercurl',
                \'strikethrough', 'reverse', 'inverse', 'italic', 'standout'],
                                  \'!empty(synIDattr(id, v:val))') + ta, ',')
      endfor
      call map(at, '!empty(v:val) ? v:val : "NONE"')
      call execute('highlight ' . th . ' ' .
                                    \join(map(items(at), 'join(v:val, "=")')))
    endif
  endfor
endfunction

function! s:ColorClass(cn, lv) abort
  if empty(a:cn) | return a:cn | endif
  if a:cn[0] != '#'
    let cn = a:cn % 256
    if cn < 16
      let cv = [[0, 0, 0], [128, 0, 0], [0, 128, 0], [128, 128, 0],
                \[0, 0, 128], [128, 0, 128], [0, 128, 128], [192, 192, 192],
                \[128, 128, 128], [255, 0, 0], [0, 255, 0], [255, 255, 0],
                \[0, 0, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255]]
      if &t_Co < 256
        let [cv[9], cv[12], cv[11], cv[14]] = [cv[12], cv[9], cv[14], cv[11]]
      endif
      let rgb = cv[cn]
    elseif cn < 232
      let cv = [0, 95, 135, 175, 215, 255]
      let cn -= 16
      let rgb = [cv[(cn / 36) % 6], cv[(cn / 6) % 6], cv[cn % 6]]
    else
      let cn = 10 * (cn - 232) + 8
      let rgb = [cn, cn, cn]
    endif
  else
    let rgb = map(split(a:cn[1:], '..\zs'), 'str2nr(v:val, 16)')
  endif
  let cl = [[0, 0, 0, 0, 1, 1, 1, 1], [0, 0, 0, 0, 1, 1, 2, 2],
                                              \[0, 1, 2, 3, 4, 5, 6, 7]][a:lv]
  call map(rgb, 'v:val / 32')
  if max(rgb) == min(rgb)
    return '99' . cl[(rgb[0] + rgb[1] + rgb[2]) / 3]
  else
    return join(map(rgb, 'cl[v:val]'), '')
  endif
endfunction

" --------------------------------------
" Common
" --------------------------------------

function! s:TraceDiffChar(u1, u2, ih) abort
  " An O(NP) Sequence Comparison Algorithm
  let [u1, u2, eq, e1, e2] = [a:u1, a:u2, '=', '-', '+']
  let [n1, n2] = [len(u1), len(u2)]
  if u1 ==# u2 | return repeat(eq, n1)
  elseif n1 == 0 | return repeat(e2, n2)
  elseif n2 == 0 | return repeat(e1, n1)
  endif
  let [N, M, u1, u2] = (n1 >= n2) ? [n1, n2, u1, u2] : [n2, n1, u2, u1]
  if n1 < n2 | let [e1, e2] = [e2, e1] | endif
  let D = N - M
  let fp = repeat([-1], M + N + 1)
  let etree = []    " [next edit, previous p, previous k]
  let p = -1
  while fp[D] != N
    let p += 1
    let epk = repeat([[]], p * 2 + D + 1)
    for k in range(-p, D - 1, 1) + range(D + p, D, -1)
      let [y, epk[k]] = (fp[k - 1] + 1 > fp[k + 1]) ?
                        \[fp[k - 1] + 1, [e1, [(k > D) ? p - 1 : p, k - 1]]] :
                        \[fp[k + 1], [e2, [(k < D) ? p - 1 : p, k + 1]]]
      let x = y - k
      while x < M && y < N && u2[x] ==# u1[y]
        let epk[k][0] .= eq | let [x, y] += [1, 1]
      endwhile
      let fp[k] = y
    endfor
    let etree += [epk]
  endwhile
  let ses = ''
  while 1
    let ses = etree[p][k][0] . ses
    if [p, k] == [0, 0] | break | endif
    let [p, k] = etree[p][k][1]
  endwhile
  let ses = ses[1 :]
  return a:ih ? s:ReduceDiffHunk(a:u1, a:u2, ses) : ses
endfunction

function! s:ReduceDiffHunk(u1, u2, ses) abort
  " in ==++++/==----, if == units equal to last ++/-- units, swap their SESs
  " (AB vs AxByAB : =+=+++ -> =++++= -> ++++==)
  let [eq, e1, e2] = ['=', '-', '+']
  let [p1, p2] = [-1, -1] | let ses = '' | let ez = ''
  for ed in reverse(split(a:ses, '[+-]\+\zs'))
    let es = ed . ez | let ez = '' | let qe = count(es, eq)
    if 0 < qe
      let [q1, q2] = [count(es, e1), count(es, e2)]
      let [uu, pp, qq] = (qe <= q1 && q2 == 0) ? [a:u1, p1, q1] :
                        \(q1 == 0 && qe <= q2) ? [a:u2, p2, q2] : [[], 0, 0]
      if !empty(uu) && uu[pp - qq - qe + 1 : pp - qq] ==# uu[pp - qe + 1 : pp]
        let ez = es[-qe :] . es[qe : -qe - 1] | let es = es[: qe - 1]
      else
        let [p1, p2] -= [q1, q2]
      endif
    endif
    let [p1, p2] -= [qe, qe]
    let ses = es . ses
  endfor
  let ses = ez . ses
  return ses
endfunction

let s:Diff = function('s:TraceDiffChar')
if get(g:, 'BuiltinDiffFunc', 0) &&
                      \(has('nvim') ? type(luaeval('vim.diff')) == v:t_func :
                                    \exists('*diff') && has('patch-9.1.0099'))
  function! s:ApplyDiffFunc(u1, u2, ih) abort
    let [eq, e1, e2] = ['=', '-', '+']
    let [n1, n2] = [len(a:u1), len(a:u2)]
    if a:u1 ==# a:u2 | return repeat(eq, n1)
    elseif n1 == 0 | return repeat(e2, n2)
    elseif n2 == 0 | return repeat(e1, n1)
    endif
    let ses = ''
    let vd = s:DiffFunc(a:u1, a:u2)
    if !empty(vd)
      let p1 = 0
      for [i1, c1, i2, c2] in vd + [[n1, 0, 0, 0]]
        let ses .= repeat(eq, i1 - p1) . repeat(e1, c1) . repeat(e2, c2)
        let p1 = i1 + c1
      endfor
    endif
    return a:ih ? s:ReduceDiffHunk(a:u1, a:u2, ses) : ses
  endfunction
  let s:Diff = function('s:ApplyDiffFunc')
  if has('nvim')
    function! s:DiffFunc(u1, u2) abort
      return map(v:lua.vim.diff(join(a:u1, "\n") . "\n",
                        \join(a:u2, "\n") . "\n", #{result_type: 'indices'}),
                            \'[v:val[0] - ((0 < v:val[1]) ? 1 : 0), v:val[1],
                            \v:val[2] - ((0 < v:val[3]) ? 1 : 0), v:val[3]]')
    endfunction
  else
    function! s:DiffFunc(u1, u2) abort
      return map(diff(a:u1, a:u2, #{output: 'indices'}),
          \'[v:val.from_idx, v:val.from_count, v:val.to_idx, v:val.to_count]')
    endfunction
  endif
endif

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

function! s:EchoWarning(msg) abort
  call execute(['echohl WarningMsg', 'echo a:msg', 'echohl None'], '')
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
