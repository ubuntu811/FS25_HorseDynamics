import numpy as np
def bc3(buf,n):
    b=np.frombuffer(buf,np.uint8).reshape(n//4,n//4,16).astype(np.int32)
    a0,a1=b[...,0],b[...,1]
    bits=np.zeros(b.shape[:2],np.uint64)
    for i in range(6): bits|=(b[...,2+i].astype(np.uint64)<<np.uint64(8*i))
    pal=np.zeros(b.shape[:2]+(8,)); pal[...,0],pal[...,1]=a0,a1
    gt=a0>a1
    for k in range(1,7):
        pal[...,k+1]=np.where(gt,((7-k)*a0+k*a1)/7.0,np.where(k<=5,((5-k)*a0+k*a1)/5.0,0.0))
    pal[...,7]=np.where(gt,(1*a0+6*a1)/7.0,255.0)
    alph=np.zeros(b.shape[:2]+(16,))
    for i in range(16):
        code=((bits>>np.uint64(3*i))&np.uint64(7)).astype(int)
        alph[...,i]=np.take_along_axis(pal,code[...,None],2)[...,0]
    c0=(b[...,8]|(b[...,9]<<8)); c1=(b[...,10]|(b[...,11]<<8))
    def rgb(c): return np.stack([((c>>11)&31)*255/31.0,((c>>5)&63)*255/63.0,(c&31)*255/31.0],-1)
    C0,C1=rgb(c0),rgb(c1); cols=np.stack([C0,C1,(2*C0+C1)/3,(C0+2*C1)/3],2)
    idx=np.zeros(b.shape[:2],np.uint32)
    for i in range(4): idx|=(b[...,12+i].astype(np.uint32)<<np.uint32(8*i))
    out=np.zeros((n,n,4))
    for i in range(16):
        code=((idx>>np.uint32(2*i))&3).astype(int)
        col=np.take_along_axis(cols,code[...,None,None].repeat(3,-1),2)[...,0,:]
        y,x=divmod(i,4); out[y::4,x::4,:3]=col; out[y::4,x::4,3]=alph[...,i]
    return out/255.0
def means(path,upto=7):
    d=open(path,"rb").read(); off=128;n=1024; res=[]
    for lv in range(upto):
        sz=(n//4)*(n//4)*16; a=bc3(d[off:off+sz],n); res.append((n,a)); off+=sz;n//=2
    return res
