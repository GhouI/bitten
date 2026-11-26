#!/usr/bin/env python3
"""Compile a Metal library (.metallib) for bitten's software Metal device.

    metal-compile.py LIBRARY OUTDIR [CLANG]

A metallib holds one AIR module per function; AIR is LLVM bitcode, which
clang compiles for x86-64 as it is. For each function this writes, in
OUTDIR:
  shaders.so     every function, plus:
                   - the air.* intrinsics it calls, defined in LLVM IR
                     (math, conversions) or in metal-runtime.c (textures);
                   - bn_call_<name>(const void *args, void *out): the
                     function called with its arguments read from 16-byte
                     slots in args and its results stored to 16-byte
                     slots in out;
  manifest.txt   per function: its kind, arguments and outputs, e.g.
                   function text_vertex vertex
                   arg 0 vertex_id
                   arg 2 buffer 0
                   out 0 position
                   out 1 user color float4
Exit status 0 on success; diagnostics on stderr."""
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def functions(path):
    """(name, bitcode) for each module in the library."""
    b = open(path, 'rb').read()
    if b[:4] != b'MTLB':
        raise SystemExit('not a metallib')
    out = []
    for m in re.finditer(b'\xde\xc0\x17\x0b', b):  # bitcode wrapper magic
        o = m.start()
        _, _, off, size, _ = struct.unpack('<IIIII', b[o:o + 20])
        out.append(b[o:o + off + size])
    return out


def split_args(s):
    """Top-level comma-separated parts of an argument list."""
    parts, depth, cur = [], 0, ''
    for ch in s:
        if ch in '<{([':
            depth += 1
        elif ch in '>})]':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


def arg_type(a):
    """The IR type of a parameter declaration, without attributes."""
    m = re.match(r'(<\d+ x \w+>|\{[^}]*\}|<\{[^}]*\}>|ptr addrspace\(\d+\)|ptr|i\d+|float|half|double)', a)
    return m.group(1)


def ret_types(t):
    t = t.strip()
    if t.startswith('<{') and t.endswith('}>'):
        return split_args(t[2:-2])
    if t.startswith('{') and t.endswith('}'):
        return split_args(t[1:-1])
    return [t]


# ---- the intrinsics ----

def vec(t):
    m = re.match(r'<(\d+) x (\w+)>', t)
    return (int(m.group(1)), m.group(2)) if m else (1, t)


def llvm_suffix(t):
    n, e = vec(t)
    base = {'float': 'f32', 'half': 'f16', 'double': 'f64'}.get(e, e)
    return 'v%d%s' % (n, base) if n > 1 else base


def splat(t, scalar_value):
    n, e = vec(t)
    if n == 1:
        return scalar_value
    return '<' + ', '.join('%s %s' % (e, scalar_value) for _ in range(n)) + '>'


def define_intrinsic(decl):
    """An IR definition for an air.* declaration, or None."""
    m = re.match(r'declare (.+?) @(air\.[\w.]+)\((.*)\)', decl)
    if not m:
        return None
    rt, name, params = m.group(1).strip(), m.group(2), split_args(m.group(3))
    ptypes = [arg_type(p) for p in params]
    args = ', '.join('%s %%a%d' % (t, i) for i, t in enumerate(ptypes))
    head = 'define internal %s @%s(%s) alwaysinline {\n' % (rt, name, args)
    op = name.split('.')[1]
    sfx = llvm_suffix(rt)
    body = None
    if op.startswith('fast_'):
        op = op[5:]
    if op in ('clamp',):
        body = ('  %%m = call %s @llvm.maxnum.%s(%s %%a0, %s %%a1)\n  %%r = call %s @llvm.minnum.%s(%s %%m, %s %%a2)\n  ret %s %%r\n'
                % (rt, sfx, rt, rt, rt, sfx, rt, rt, rt))
    elif op in ('fmax', 'fmin'):
        f = 'maxnum' if op == 'fmax' else 'minnum'
        body = '  %%r = call %s @llvm.%s.%s(%s %%a0, %s %%a1)\n  ret %s %%r\n' % (rt, f, sfx, rt, rt, rt)
    elif op in ('fabs', 'floor', 'sqrt', 'exp', 'sin', 'cos', 'ceil', 'trunc', 'exp2', 'log', 'log2', 'round'):
        f = {'fabs': 'fabs', 'round': 'round'}.get(op, op)
        body = '  %%r = call %s @llvm.%s.%s(%s %%a0)\n  ret %s %%r\n' % (rt, f, sfx, rt, rt)
    elif op == 'rsqrt':
        body = ('  %%s = call %s @llvm.sqrt.%s(%s %%a0)\n  %%r = fdiv %s %s, %%s\n  ret %s %%r\n'
                % (rt, sfx, rt, rt, splat(rt, '1.0'), rt))
    elif op == 'pow':
        body = '  %%r = call %s @llvm.pow.%s(%s %%a0, %s %%a1)\n  ret %s %%r\n' % (rt, sfx, rt, rt, rt)
    elif op == 'mix':
        body = ('  %%d = fsub %s %%a1, %%a0\n  %%p = fmul %s %%d, %%a2\n  %%r = fadd %s %%a0, %%p\n  ret %s %%r\n'
                % (rt, rt, rt, rt))
    elif op == 'saturate':
        body = ('  %%m = call %s @llvm.maxnum.%s(%s %%a0, %s)\n  %%r = call %s @llvm.minnum.%s(%s %%m, %s)\n  ret %s %%r\n'
                % (rt, sfx, rt, splat(rt, '0.0'), rt, sfx, rt, splat(rt, '1.0'), rt))
    elif op == 'dot':
        t = ptypes[0]
        n, _ = vec(t)
        body = '  %%p = fmul %s %%a0, %%a1\n' % t
        acc = None
        for i in range(n):
            body += '  %%e%d = extractelement %s %%p, i32 %d\n' % (i, t, i)
            if acc is None:
                acc = '%%e%d' % i
            else:
                body += '  %%s%d = fadd float %s, %%e%d\n' % (i, acc, i)
                acc = '%%s%d' % i
        body += '  ret float %s\n' % acc
    elif op in ('all', 'any'):
        f = 'and' if op == 'all' else 'or'
        body = '  %%r = call i1 @llvm.vector.reduce.%s.%s(%s %%a0)\n  ret i1 %%r\n' % (f, llvm_suffix(ptypes[0]), ptypes[0])
    elif op == 'convert':
        # air.convert.<to kind>.<to type>.<from kind>.<from type>
        parts = name.split('.')
        to_k, from_k = parts[2], parts[4]
        src = ptypes[0]
        _, se = vec(src)
        _, de = vec(rt)
        if to_k == 'f' and from_k in ('u', 's'):
            ins = 'uitofp' if from_k == 'u' else 'sitofp'
        elif to_k in ('u', 's') and from_k == 'f':
            ins = 'fptoui' if to_k == 'u' else 'fptosi'
        elif to_k == 'f' and from_k == 'f':
            ins = 'fpext' if se == 'half' else 'fptrunc' if de == 'half' else 'bitcast'
        else:
            sb, db = int(se[1:]), int(de[1:])
            ins = 'trunc' if db < sb else ('sext' if from_k == 's' else 'zext') if db > sb else 'bitcast'
        if ins in ('uitofp', 'fptoui') and False:
            pass
        body = '  %%r = %s %s %%a0 to %s\n  ret %s %%r\n' % (ins, src, rt, rt)
    elif op == 'get_height_texture_2d' or op == 'get_width_texture_2d':
        which = 'height' if 'height' in op else 'width'
        body = '  %%r = call i32 @bn_tex_%s(ptr addrspace(1) %%a0)\n  ret i32 %%r\n' % which
    elif op == 'read_texture_2d':
        # (texture, coord <2 x i32>, lod, ...) -> { <4 x float>, i8 }
        body = ('  %%x = extractelement <2 x i32> %%a1, i32 0\n  %%y = extractelement <2 x i32> %%a1, i32 1\n'
                '  %%buf = alloca <4 x float>, align 16\n'
                '  call void @bn_tex_read(ptr addrspace(1) %%a0, i32 %%x, i32 %%y, ptr %%buf)\n'
                '  %%v = load <4 x float>, ptr %%buf, align 16\n'
                '  %%r0 = insertvalue %s poison, <4 x float> %%v, 0\n  %%r = insertvalue %s %%r0, i8 0, 1\n  ret %s %%r\n'
                % (rt, rt, rt))
    elif op == 'sample_texture_2d':
        # (texture, sampler, coord <2 x float>, ...) -> { <4 x float>, i8 }
        body = ('  %%u = extractelement <2 x float> %%a2, i32 0\n  %%v0 = extractelement <2 x float> %%a2, i32 1\n'
                '  %%buf = alloca <4 x float>, align 16\n'
                '  call void @bn_tex_sample(ptr addrspace(1) %%a0, ptr addrspace(2) %%a1, float %%u, float %%v0, ptr %%buf)\n'
                '  %%v = load <4 x float>, ptr %%buf, align 16\n'
                '  %%r0 = insertvalue %s poison, <4 x float> %%v, 0\n  %%r = insertvalue %s %%r0, i8 0, 1\n  ret %s %%r\n'
                % (rt, rt, rt))
    if body is None:
        sys.stderr.write('metal-compile: no definition for %s\n' % name)
        return None
    return head + body + '}\n'


RUNTIME_DECLS = '''
declare i32 @bn_tex_height(ptr addrspace(1))
declare i32 @bn_tex_width(ptr addrspace(1))
declare void @bn_tex_read(ptr addrspace(1), i32, i32, ptr)
declare void @bn_tex_sample(ptr addrspace(1), ptr addrspace(2), float, float, ptr)
'''


# ---- the metadata ----

def parse_metadata(ll):
    """{id: text} for the module's numbered metadata."""
    md = {}
    for m in re.finditer(r'^!(\d+) = (?:distinct )?!\{(.*)\}$', ll, re.M):
        md[m.group(1)] = m.group(2)
    return md


def entries(text):
    return split_args(text)


def describe(ll, name):
    """(kind, args, outputs) for the module's entry point."""
    md = parse_metadata(ll)
    kind = None
    for k in ('vertex', 'fragment', 'kernel'):
        m = re.search(r'^!air\.%s = !\{(.*)\}' % k, ll, re.M)
        if m:
            kind = k
            ref = entries(m.group(1))[0].lstrip('!')
            break
    if not kind:
        return None
    top = entries(md[ref])
    outs_ref, ins_ref = top[1].lstrip('!'), top[2].lstrip('!')
    outs = []
    if kind == 'fragment' or kind == 'vertex':
        for e in entries(md[outs_ref]) if outs_ref in md else []:
            fields = entries(md[e.lstrip('!')])
            tag = fields[0].strip('!"')
            tname = arg_name = ''
            for i, f in enumerate(fields):
                if f == '!"air.arg_type_name"':
                    tname = fields[i + 1].strip('!"')
                if f == '!"air.arg_name"':
                    arg_name = fields[i + 1].strip('!"')
            if tag == 'air.position':
                outs.append('position')
            elif tag == 'air.vertex_output':
                outs.append('user %s %s' % (fields[1].strip('!"'), tname))
            elif tag == 'air.render_target':
                outs.append('color %s' % fields[1].split()[-1] if len(fields) > 1 else 'color 0')
            else:
                outs.append('other %s' % tag)
    args = []
    for e in entries(md[ins_ref]):
        fields = entries(md[e.lstrip('!')])
        idx = fields[0].split()[-1]
        tag = fields[1].strip('!"')
        if tag in ('air.vertex_id', 'air.instance_id', 'air.position', 'air.front_facing', 'air.sample_id',
                   'air.base_vertex', 'air.base_instance'):
            args.append('arg %s %s' % (idx, tag[4:]))
        elif tag == 'air.buffer' or tag == 'air.texture' or tag == 'air.sampler':
            loc = '0'
            for i, f in enumerate(fields):
                if f == '!"air.location_index"':
                    loc = fields[i + 1].split()[-1]
            size = ''
            for i, f in enumerate(fields):
                if f == '!"air.arg_type_size"':
                    size = ' ' + fields[i + 1].split()[-1]
            args.append('arg %s %s %s%s' % (idx, tag[4:], loc, size))
        elif tag == 'air.fragment_input':
            args.append('arg %s input %s' % (idx, fields[2].strip('!"')))
        elif tag == 'air.stage_in':
            args.append('arg %s stage_in' % idx)
        else:
            args.append('arg %s other %s' % (idx, tag))
    return kind, args, outs


# ---- putting it together ----

def wrapper(ll, name):
    m = re.search(r'^define (.+?) @%s\((.*)\) [^{]*\{' % re.escape(name), ll, re.M)
    rt, params = m.group(1), split_args(m.group(2))
    rt = re.sub(r'^(noundef |nonnull |signext |zeroext )+', '', rt).strip()
    ptypes = [arg_type(p) for p in params]
    w = 'define void @bn_call_%s(ptr %%args, ptr %%out) {\n' % name
    names = []
    for i, t in enumerate(ptypes):
        w += '  %%p%d = getelementptr i8, ptr %%args, i64 %d\n' % (i, 16 * i)
        w += '  %%v%d = load %s, ptr %%p%d, align 1\n' % (i, t, i)
        names.append('%s %%v%d' % (t, i))
    if rt == 'void':
        w += '  call void @%s(%s)\n' % (name, ', '.join(names))
    else:
        w += '  %%r = call %s @%s(%s)\n' % (rt, name, ', '.join(names))
        elems = ret_types(rt)
        if len(elems) == 1 and not (rt.startswith('<{') or rt.startswith('{')):
            w += '  store %s %%r, ptr %%out, align 1\n' % rt
        else:
            for j, t in enumerate(elems):
                w += '  %%e%d = extractvalue %s %%r, %d\n' % (j, rt, j)
                w += '  %%o%d = getelementptr i8, ptr %%out, i64 %d\n' % (j, 16 * j)
                w += '  store %s %%e%d, ptr %%o%d, align 1\n' % (t, j, j)
    w += '  ret void\n}\n'
    return w


def main():
    lib, out = sys.argv[1], sys.argv[2]
    clang = sys.argv[3] if len(sys.argv) > 3 else os.environ.get('BITTEN_CLANG', 'clang')
    os.makedirs(out, exist_ok=True)
    manifest = []
    objects = []
    for i, bc in enumerate(functions(lib)):
        bcp = os.path.join(out, 'f%d.bc' % i)
        open(bcp, 'wb').write(bc)
        llp = os.path.join(out, 'f%d.ll' % i)
        subprocess.run([clang, '-S', '-emit-llvm', '-x', 'ir', bcp, '-o', llp, '-Wno-override-module'], check=True,
                       stderr=subprocess.DEVNULL)
        ll = open(llp).read()
        names = [n for n in re.findall(r'^define [^@]*@(\w+)\(', ll, re.M)
                 if re.search(r'^!air\.(vertex|fragment|kernel) = !\{!(\d+)\}', ll, re.M)]
        d = None
        name = None
        for n in names:
            d = describe(ll, n)
            if d and re.search(r'!\{ptr @%s,' % re.escape(n), ll):
                name = n
                break
        if not name:
            continue
        kind, args, outs = d
        manifest.append('function %s %s' % (name, kind))
        manifest += args
        manifest += ['out %d %s' % (j, o) for j, o in enumerate(outs)]
        # strip the air module metadata that names functions in other modules; define intrinsics
        body = re.sub(r'^declare [^@]*@air\..*$', '', ll, flags=re.M)
        defs = [define_intrinsic(dl) for dl in re.findall(r'^declare [^@]*@air\..*$', ll, re.M)]
        body += '\n' + RUNTIME_DECLS + '\n'.join(x for x in defs if x) + '\n' + wrapper(ll, name)
        # internalize everything but the wrapper so modules link together
        body = re.sub(r'^define (?!internal|void @bn_call_)', 'define internal ', body, flags=re.M)
        body = body.replace('section "air.static_init"', '')
        open(llp, 'w').write(body)
        o = os.path.join(out, 'f%d.o' % i)
        subprocess.run([clang, '-c', '-O2', '-fPIC', '-x', 'ir', llp, '-o', o, '-Wno-override-module'], check=True)
        objects.append(o)
    rt = os.path.join(HERE, 'metal-runtime.c')
    so = os.path.join(out, 'shaders.so')
    subprocess.run([clang, '-O2', '-fPIC', '-shared', '-o', so, rt] + objects, check=True)
    open(os.path.join(out, 'manifest.txt'), 'w').write('\n'.join(manifest) + '\n')


if __name__ == '__main__':
    main()
