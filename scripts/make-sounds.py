#!/usr/bin/env python3
# Usage: python3 scripts/make-sounds.py NotchBuddy/Resources/sounds
# Rafiq's sounds: synthesized from scratch (soft kalimba, bells, glides, noise),
# 48 kHz stereo 16-bit, like the files they replace.
import numpy as np, wave, sys, os
SR=48000
rng=np.random.default_rng(7)
def t(d): return np.arange(int(SR*d))/SR
def note(f, d, amp=1.0, decay=6.0, bright=0.35, bell=False, attack=0.004):
    x=t(d)
    env=np.exp(-decay*x)*np.minimum(1,x/attack)
    s=np.sin(2*np.pi*f*x)
    s+=bright*np.exp(-decay*2.5*x)*np.sin(2*np.pi*f*(4.0 if not bell else 2.76)*x)
    if bell: s+=0.25*np.exp(-decay*1.6*x)*np.sin(2*np.pi*f*5.4*x)
    else: s+=0.12*np.sin(2*np.pi*f*2*x)*np.exp(-decay*1.5*x)
    return amp*env*s
def glide(f0,f1,d,amp=1.0,decay=3.0,shape='exp',vib=0,vibf=6):
    x=t(d); k=x/d
    f=f0*(f1/f0)**k if shape=='exp' else f0+(f1-f0)*k
    if vib: f=f*(1+vib*np.sin(2*np.pi*vibf*x))
    ph=2*np.pi*np.cumsum(f)/SR
    env=np.exp(-decay*x)*np.minimum(1,x/0.01)*np.minimum(1,(d-x)/0.03)
    return amp*env*(np.sin(ph)+0.15*np.sin(2*ph))
def noise(d,amp=1.0,decay=20.0,lp=0.3):
    x=t(d); n=rng.standard_normal(len(x))
    # one-pole low-pass
    y=np.zeros_like(n); a=lp
    for i in range(1,len(n)): y[i]=y[i-1]+a*(n[i]-y[i-1])
    return amp*y*np.exp(-decay*x)
def seq(parts, total=None):
    end=max(int(SR*o)+len(p) for o,p in parts)
    if total: end=max(end,int(SR*total))
    out=np.zeros(end)
    for o,p in parts: i=int(SR*o); out[i:i+len(p)]+=p
    return out
def hz(n): return 440*2**((n-69)/12)   # MIDI note
def save(name, mono, gain=0.55, pan=0.0):
    mono=mono/ (np.max(np.abs(mono))+1e-9) * gain
    fade=min(len(mono), int(SR*0.01)); mono[-fade:]*=np.linspace(1,0,fade)
    l=mono*(1-max(0,pan)); r=mono*(1+min(0,pan))
    st=np.stack([l,r],1)
    st=np.clip(st,-1,1); data=(st*32767).astype('<i2').tobytes()
    with wave.open(os.path.join(sys.argv[1],name+'.wav'),'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
# Hijaz on D: D Eb F# G A Bb C D
H=[62,63,66,67,69,70,72,74,75,78,79,81]
save('peek', seq([(0,note(hz(H[4]+12),0.3,decay=9)),(0.09,note(hz(H[7]+12),0.35,decay=9))]),0.45)
save('open', seq([(0,glide(500,900,0.18,0.5,4)),(0.08,note(hz(H[7]+12),0.4,decay=7,bell=True))]),0.45)
save('close', seq([(0,note(hz(H[7]+12),0.3,decay=10,bell=True)),(0.07,glide(800,420,0.2,0.5,6))]),0.4)
save('hover', note(hz(93),0.08,decay=45,bright=0.2),0.06)
save('blip', note(hz(88),0.1,decay=30),0.08)
save('slap', seq([(0,noise(0.12,1,30,0.6)),(0,glide(180,70,0.25,1.2,10))]),0.6)
save('annoyed', seq([(0,glide(420,300,0.25,1,3,vib=0.03,vibf=18)),(0.27,glide(330,240,0.3,1,4,vib=0.04,vibf=18))]),0.5)
save('dizzy', glide(700,300,0.95,1,1.5,vib=0.12,vibf=7),0.45)
save('greet', seq([(0,note(hz(H[0]+12),0.4,decay=6)),(0.12,note(hz(H[2]+12),0.4,decay=6)),(0.24,note(hz(H[4]+12),0.5,decay=5))]),0.5)
save('work', seq([(0,note(hz(H[3]+12),0.25,decay=12)),(0.1,note(hz(H[4]+12),0.28,decay=12))]),0.35)
save('finish', seq([(0,note(hz(H[0]+12),0.5,decay=5)),(0.11,note(hz(H[2]+12),0.5,decay=5)),(0.22,note(hz(H[4]+12),0.5,decay=5)),(0.36,note(hz(H[7]+12),0.8,decay=3.5,bell=True))]),0.55)
save('error', seq([(0,note(hz(H[5]),0.4,decay=6,bright=0.5)),(0.18,note(hz(H[1]),0.6,decay=4,bright=0.5))]),0.55)
save('approval', seq([(0,note(hz(H[4]+12),0.35,decay=7,bell=True)),(0.2,note(hz(H[4]+12),0.6,decay=5,bell=True))]),0.55)
save('question', seq([(0,note(hz(H[3]+12),0.3,decay=8)),(0.15,note(hz(H[6]+12),0.5,decay=6))]),0.5)
save('approve', seq([(0,note(hz(H[4]+12),0.5,decay=6)),(0,note(hz(H[7]+12),0.5,decay=6,amp=0.7)),(0.0,note(hz(H[2]+12),0.5,decay=6,amp=0.5))]),0.5)
save('gulp', seq([(0,glide(500,160,0.18,1,6)),(0.2,glide(260,120,0.3,0.6,8))]),0.5)
save('tick', note(hz(96),0.07,decay=60,bright=0.6),0.12)
save('send', seq([(0,noise(0.35,0.4,8,0.15)),(0,glide(400,1300,0.35,0.8,3))]),0.45)
save('love', seq([(0,note(hz(H[7]+12),0.6,decay=4,bell=True)),(0.15,note(hz(H[9]+12),0.6,decay=4,bell=True)),(0.3,note(hz(H[11]+12),0.5,decay=4,bell=True))]),0.45)
save('pop', seq([(0,glide(300,900,0.06,1,10)),(0.05,note(hz(84),0.3,decay=18))]),0.45)
save('proud', seq([(0,note(hz(H[4]),0.25,decay=6)),(0.12,note(hz(H[4]),0.2,decay=8)),(0.24,note(hz(H[7]),0.6,decay=4,bright=0.5))]),0.55)
save('wink', seq([(0,glide(700,1100,0.08,1,8)),(0.09,glide(1100,800,0.1,1,10))]),0.35)
save('yawn', glide(520,200,0.72,1,1.2,vib=0.01,vibf=5),0.4)
save('attach', seq([(0,noise(0.04,1,60,0.7)),(0.06,note(hz(H[7]+12),0.6,decay=6,bell=True))]),0.45)
save('think', seq([(0,note(hz(H[1]+12),0.3,decay=7,bright=0.1)),(0.16,note(hz(H[0]+12),0.3,decay=7,bright=0.1))]),0.35)
save('search', seq([(0,note(hz(H[7]+12),0.45,decay=5,bell=True)),(0.0,glide(1200,1500,0.4,0.15,8))]),0.4)
save('rate', seq([(0,note(hz(H[7]+12),0.3,decay=10,bell=True)),(0.08,note(hz(H[9]+12),0.3,decay=10,bell=True)),(0.16,note(hz(H[11]+12),0.5,decay=6,bell=True))]),0.4)
save('sleep', seq([(0,note(hz(H[4]),0.3,decay=6,bright=0.1)),(0.15,note(hz(H[2]),0.3,decay=6,bright=0.1))]),0.35)
# The greeting: a short Hijaz phrase, D Eb F# G A, then Bb A G F# and a bell on D.
mel=[(0,0,0.35),(0.22,1,0.35),(0.44,2,0.5),(0.74,3,0.35),(0.96,4,0.8),(1.5,5,0.35),(1.72,4,0.35),(1.94,3,0.35),(2.16,2,0.6),(2.6,0,1.6)]
parts=[(o,note(hz(H[i]+12),d+0.4,decay=3.2 if d<1 else 1.6,bell=(o>=2.6))) for o,i,d in mel]
parts+= [(o,note(hz(H[i]),d+0.4,amp=0.25,decay=3,bright=0.1)) for o,i,d in mel[::2]]
save('greeting', seq(parts,total=4.2),0.55)
print('ok', len(os.listdir(sys.argv[1])))
