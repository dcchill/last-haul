"""Original pixel materials and physical-sign textures. Python standard library only."""
from pathlib import Path
import hashlib, json, math, random, struct, zlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'medtac'
OUT.mkdir(parents=True, exist_ok=True)

FONT = {
'A':['01110','10001','10001','11111','10001','10001','10001'],
'B':['11110','10001','10001','11110','10001','10001','11110'],
'C':['01111','10000','10000','10000','10000','10000','01111'],
'D':['11110','10001','10001','10001','10001','10001','11110'],
'E':['11111','10000','10000','11110','10000','10000','11111'],
'F':['11111','10000','10000','11110','10000','10000','10000'],
'G':['01111','10000','10000','10111','10001','10001','01110'],
'H':['10001','10001','10001','11111','10001','10001','10001'],
'I':['11111','00100','00100','00100','00100','00100','11111'],
'J':['00111','00010','00010','00010','10010','10010','01100'],
'K':['10001','10010','10100','11000','10100','10010','10001'],
'L':['10000','10000','10000','10000','10000','10000','11111'],
'M':['10001','11011','10101','10101','10001','10001','10001'],
'N':['10001','11001','10101','10011','10001','10001','10001'],
'O':['01110','10001','10001','10001','10001','10001','01110'],
'P':['11110','10001','10001','11110','10000','10000','10000'],
'Q':['01110','10001','10001','10001','10101','10010','01101'],
'R':['11110','10001','10001','11110','10100','10010','10001'],
'S':['01111','10000','10000','01110','00001','00001','11110'],
'T':['11111','00100','00100','00100','00100','00100','00100'],
'U':['10001','10001','10001','10001','10001','10001','01110'],
'V':['10001','10001','10001','10001','10001','01010','00100'],
'W':['10001','10001','10001','10101','10101','10101','01010'],
'X':['10001','10001','01010','00100','01010','10001','10001'],
'Y':['10001','10001','01010','00100','00100','00100','00100'],
'Z':['11111','00001','00010','00100','01000','10000','11111'],
'0':['01110','10001','10011','10101','11001','10001','01110'],
'1':['00100','01100','00100','00100','00100','00100','01110'],
'2':['01110','10001','00001','00010','00100','01000','11111'],
'3':['11110','00001','00001','01110','00001','00001','11110'],
'4':['00010','00110','01010','10010','11111','00010','00010'],
'5':['11111','10000','10000','11110','00001','00001','11110'],
'6':['01110','10000','10000','11110','10001','10001','01110'],
'7':['11111','00001','00010','00100','01000','01000','01000'],
'8':['01110','10001','10001','01110','10001','10001','01110'],
'9':['01110','10001','10001','01111','00001','00001','01110'],
'-':['00000','00000','00000','11111','00000','00000','00000'],
'/':['00001','00010','00010','00100','01000','01000','10000'],
':':['00000','00100','00100','00000','00100','00100','00000'],
'.':['00000','00000','00000','00000','00000','00100','00100'],
'>':['10000','01000','00100','00010','00100','01000','10000'],
'<':['00001','00010','00100','01000','00100','00010','00001'],
' ':['00000']*7,
}

def png(path, w, h, pixels):
    def chunk(tag,data):
        return struct.pack('!I',len(data))+tag+data+struct.pack('!I',zlib.crc32(tag+data)&0xffffffff)
    data=b''.join(b'\x00'+bytes(pixels[y*w*3:(y+1)*w*3]) for y in range(h))
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(data,9))+chunk(b'IEND',b''))

def text_on(pixels,w,h,text,x,y,scale,color):
    for char in text.upper():
        for gy,row in enumerate(FONT.get(char,FONT[' '])):
            for gx,bit in enumerate(row):
                if bit=='0': continue
                for dy in range(scale):
                    for dx in range(scale):
                        px=x+gx*scale+dx; py=y+gy*scale+dy
                        if 0<=px<w and 0<=py<h: pixels[(py*w+px)*3:(py*w+px)*3+3]=color
        x+=6*scale

def atlas():
    w=h=1024; pixels=bytearray(w*h*3); rng=random.Random(7127)
    colors=[(151,160,145),(99,122,111),(68,87,82),(178,185,168),
            (78,88,82),(118,115,99),(148,121,72),(203,195,165),
            (125,143,125),(176,181,159),(42,68,63),(182,156,77),
            (101,119,127),(102,88,72),(112,101,83),(69,79,71)]
    for y in range(h):
        for x in range(w):
            tile=(y//128)*8+x//128; u=x%128; v=y%128
            base=colors[tile%16]; noise=rng.randrange(-7,8)
            seam=-24 if u<3 or v<3 else 0
            scratch=15 if (u+v*3+tile*11)%107<2 else 0
            stain=-18 if (u//18+v//24+tile)%9==0 else 0
            stripe=25 if tile%16==11 and (u+v)//12%2==0 else 0
            if tile%16==10:
                noise=10 if v in range(54,58) and u%28<19 else 0
            for c in range(3): pixels[(y*w+x)*3+c]=max(0,min(255,base[c]+noise+seam+scratch+stain+stripe))
    for tile in range(64):
        tx=(tile%8)*128; ty=(tile//8)*128
        if tile%16 in (1,3,7,9): text_on(pixels,w,h,'MEDTAC',tx+12,ty+16,2,(44,66,58))
        if tile%16==10: text_on(pixels,w,h,'SYS 19',tx+10,ty+85,2,(147,190,153))
    png(OUT/'materials.png',w,h,pixels)

def signs():
    manifest=ROOT/'.godot/medtac-signs.json'
    if not manifest.exists(): return
    for key,text in json.loads(manifest.read_text(encoding='utf-8-sig')).items():
        lines=text.upper().replace('→','>').replace('←','<').replace('↓','V').replace('↑','^').split('\n')
        lines=[line[:64] for line in lines]
        w=512; h=max(96,40+len(lines)*42)
        pixels=bytearray([38,66,61]*(w*h))
        for y in range(h):
            for x in range(w):
                if x<5 or y<5 or x>=w-5 or y>=h-5:
                    pixels[(y*w+x)*3:(y*w+x)*3+3]=bytes((164,170,143))
        for i,line in enumerate(lines):
            scale=max(1,min(4,(w-36)//max(1,len(line)*6)))
            text_on(pixels,w,h,line,(w-len(line)*6*scale)//2,20+i*42,scale,(223,222,187))
        png(OUT/'signs'/f'{key}.png',w,h,pixels)

def models():
    recipes={}
    def model(name):
        parts=[]; recipes[name]=parts
        def box(x,y,z,w,h,d,tile=1,solid=True): parts.append([x,y,z,w,h,d,tile,solid])
        return box
    def legs(b,w,d,h):
        for x in [-w/2+.08,w/2-.08]:
            for z in [-d/2+.08,d/2-.08]: b(x,h/2,z,.08,h,.08,4)
    for name in ['exam_bed','recovery_bed']:
        b=model(name); legs(b,1,2.2,.55)
        b(0,.64,0,1.05,.12,2.25,4); b(0,.79,0,.94,.2,2.1,7)
        b(0,.92,-.77,.7,.14,.45,3)
        for x in [-.52,.52]:
            b(x,.98,-.25,.06,.08,1.4,4)
            for z in [-.85,.85]: b(x,.10,z,.16,.2,.16,15)
        if name=='recovery_bed': b(0,1.1,-1.02,1.03,.55,.08,1)
    b=model('monitor_cart'); legs(b,.65,.5,.75)
    b(0,.8,0,.75,.1,.6,3); b(0,1.18,.1,.12,.75,.12,4); b(0,1.45,0,.65,.5,.15,10)
    b(0,.4,0,.65,.05,.45,4)
    b=model('iv_stand'); b(0,1,0,.06,2,.06,4); b(0,.1,0,.75,.08,.12,4); b(0,.1,0,.12,.08,.75,4)
    b(0,1.94,0,.5,.06,.06,4); b(.18,1.72,0,.2,.35,.1,3); b(.18,1.15,0,.025,.7,.025,12,False)
    b=model('exam_chair'); legs(b,.65,.7,.5); b(0,.57,0,.7,.14,.7,8); b(0,.98,-.32,.7,.8,.16,8)
    for x in [-.4,.4]: b(x,.77,0,.12,.1,.6,4)
    b=model('privacy_screen'); legs(b,1.6,.4,.2); b(0,1.1,0,1.6,1.9,.08,3)
    for x in [-.84,.84]: b(x,1.1,0,.08,2.2,.12,4)
    b=model('nurse_desk'); legs(b,2.1,1,.85); b(0,.92,0,2.2,.12,1.05,3)
    b(.65,.4,.1,.65,.8,.7,1); b(-.4,1.2,-.2,.7,.45,.13,10); b(-.4,1.02,.2,.6,.04,.25,4)
    b=model('wheel_chair'); b(0,.55,0,.6,.14,.65,8); b(0,.94,-.3,.6,.7,.14,8)
    for x in [-.4,.4]:
        b(x,.4,0,.1,.8,.8,15); b(x,.75,0,.1,.1,.6,4)
    b(0,.2,.5,.55,.08,.3,4)
    for name in ['analyzer','centrifuge','microscope','biosafety_cabinet','sample_rack','lab_fridge','ultra_freezer','autoclave','wash_station','instrument_bench']:
        b=model(name)
        if name in ['lab_fridge','ultra_freezer','autoclave']:
            h=2 if name=='lab_fridge' else 1.5
            b(0,h/2,0,1.3,h,.9,3); b(0,h/2,.47,1.12,h-.12,.06,9)
            b(.43,h*.6,.55,.06,.5,.06,4); b(-.25,h-.22,.52,.4,.2,.04,10)
            for x in [-.45,-.2,.05,.3]: b(x,.17,.52,.1,.04,.02,4,False)
        elif name=='microscope':
            b(0,.07,0,.35,.14,.45,4); b(0,.3,.1,.08,.5,.09,1)
            b(0,.55,0,.15,.13,.3,4); b(0,.65,-.1,.09,.17,.1,15); b(0,.23,-.05,.3,.04,.25,3)
        elif name=='sample_rack':
            b(0,.06,0,.6,.12,.32,9)
            for x in [-.2,-.1,0,.1,.2]:
                for z in [-.08,.08]: b(x,.2,z,.045,.27,.045,12,False); b(x,.35,z,.05,.04,.05,6,False)
        elif name=='biosafety_cabinet':
            legs(b,2,1,.8); b(0,.85,0,2.1,.1,1,4); b(0,1.2,-.42,2.1,.8,.16,3)
            for x in [-1,1]: b(x,1.5,0,.12,1.2,.9,3)
            b(0,2.05,0,2.1,.35,.9,1); b(0,1.8,.25,1.8,.35,.06,12,False)
            b(.7,.98,.15,.2,.16,.2,7,False)
        elif name=='wash_station':
            legs(b,1.7,.8,.8); b(0,.85,0,1.8,.12,.9,4); b(0,.9,0,1,.02,.5,10,False)
            b(.5,1.12,-.25,.05,.4,.05,4); b(.4,1.3,-.18,.25,.05,.2,4)
        elif name=='instrument_bench':
            legs(b,2.4,1,.85); b(0,.9,0,2.5,.1,1.1,3); b(.8,.4,0,.7,.8,.8,1)
            b(-.55,1.2,0,.8,.5,.65,9); b(-.55,1.3,.34,.5,.2,.02,10,False)
            b(.45,1.1,0,.08,.3,.08,12,False)
        else:
            b(0,.3,0,.9,.6,.7,3); b(0,.55,.37,.72,.25,.06,10)
            b(.29,.2,.4,.12,.08,.04,11,False)
            if name=='centrifuge': b(0,.68,0,.65,.15,.5,4)
            else: b(0,.8,-.15,.8,.45,.3,1); b(.25,.83,.05,.25,.2,.06,10)
    for name in ['filing_cabinet','desk_drawers','wall_cabinet','med_cabinet','staff_locker','specimen_cooler','supply_cart','personal_bag']:
        b=model(name)
        if name=='personal_bag':
            b(0,.18,0,.65,.35,.4,14); b(0,.4,0,.3,.08,.12,15); b(0,.22,.21,.5,.02,.03,6)
        elif name=='supply_cart':
            legs(b,.8,.6,.85)
            for y in [.15,.5,.85]: b(0,y,0,.9,.06,.65,4)
            for x in [-.2,.2]: b(x,.98,0,.22,.2,.28,7,False)
        elif name=='specimen_cooler':
            b(0,.3,0,.8,.6,.5,3); b(0,.65,0,.86,.12,.56,1); b(0,.37,.26,.3,.16,.02,7,False)
        else:
            w=.7 if name=='staff_locker' else 1.1
            h=2 if name=='staff_locker' else 1.5 if name in ['med_cabinet','filing_cabinet'] else .9
            b(0,h/2,0,w,h,.6,1); b(0,h/2,.32,w-.08,h-.1,.06,9)
            for y in [.2,h*.5,h-.2]: b(w*.3,y,.38,.15,.04,.04,4,False)
            if name=='desk_drawers':
                for y in [.25,.5,.75]: b(0,y,.36,w-.08,.025,.02,4,False)
    for name in ['pallet_jack','forklift','roll_cage','wrapped_pallet','conveyor','packing_table','cold_chain_crate','work_cart']:
        b=model(name)
        if name in ['pallet_jack','forklift']:
            for x in [-.4,.4]: b(x,.12,.7,.16,.15,1.6,6)
            b(0,.35,-.3,1,.7,.8,6); b(0,1,-.6,.1,1.5,.1,4)
            b(0,1.7,-.6,.65,.1,.12,15)
            if name=='forklift':
                b(0,.5,-1,1.4,.9,1.7,6); b(0,2,-1,1.5,.12,1.8,6)
                for x in [-.65,.65]:
                    b(x,1.3,-.3,.08,1.5,.08,4)
                    for z in [-1.6,-.4]: b(x,.35,z,.3,.7,.7,15)
                b(0,1,-1,.6,.6,.5,15)
        elif name=='roll_cage':
            b(0,.12,0,1.2,.18,.9,4)
            for x in [-.55,.55]:
                for z in [-.4,.4]: b(x,1,z,.06,2,.06,4)
                for y in [.6,1.2,1.8]: b(x,y,0,.04,.04,.8,4)
            b(0,.6,0,.8,.8,.6,13)
        elif name=='wrapped_pallet':
            b(0,.1,0,1.3,.2,1.1,13); b(0,.85,0,1.1,1.4,.95,9)
            for y in [.35,.8,1.25]: b(0,y,.49,1.1,.04,.025,3,False)
        elif name=='conveyor':
            legs(b,3,.85,.8)
            for x in [-1.4,-1.15,-.9,-.65,-.4,-.15,.1,.35,.6,.85,1.1,1.35]: b(x,.86,0,.17,.15,.9,4)
        elif name=='packing_table':
            legs(b,2,1,.9); b(0,.95,0,2.2,.1,1.1,13); b(.6,1.2,0,.5,.4,.5,7)
            b(-.5,1.1,0,.4,.2,.3,6)
        elif name=='cold_chain_crate':
            b(0,.6,0,1.4,1.2,1.1,3)
            for x in [-.6,.6]: b(x,.6,.57,.1,1.2,.05,4,False)
            b(0,.7,.58,.5,.25,.04,10,False)
        else:
            legs(b,1.2,.7,.8); b(0,.85,0,1.3,.1,.8,4); b(.4,1.1,0,.4,.4,.5,1)
    for name in ['server_rack','electrical_panel','air_handler','eyewash','toilet','shower','break_table','trash_bin']:
        b=model(name)
        if name=='server_rack':
            b(0,1,0,.85,2,.8,4)
            for y in [.25,.55,.85,1.15,1.45,1.75]: b(0,y,.42,.7,.22,.04,10,False)
        elif name=='electrical_panel':
            b(0,.8,0,1.1,1.6,.3,4); b(0,.9,.18,.9,.9,.04,11,False)
        elif name=='air_handler':
            b(0,1,0,2.5,2,1.2,4)
            for x in [-.9,-.3,.3,.9]: b(x,1,.62,.35,1.3,.04,10,False)
            b(0,2.2,0,1.2,.4,.8,1)
        elif name=='eyewash':
            b(0,.6,0,.08,1.2,.08,4); b(0,1.2,0,.6,.15,.4,3)
            b(0,1.4,0,.35,.06,.1,1)
        elif name=='toilet':
            b(0,.3,0,.55,.6,.65,3); b(0,.62,0,.6,.08,.7,7); b(0,.65,-.36,.65,.9,.24,3)
        elif name=='shower':
            b(0,.05,0,1.2,.1,1.2,3); b(0,1.2,-.55,.05,2.4,.05,4); b(0,2.35,-.35,.35,.06,.4,4)
        elif name=='break_table':
            legs(b,1.6,.9,.75); b(0,.8,0,1.8,.1,1,13)
            for x in [-.8,.8]: b(x,.42,.8,.45,.85,.5,8)
        else:
            b(0,.4,0,.65,.8,.6,4); b(0,.85,0,.72,.08,.65,15)
    for name in ['wall_clock','terminal','clipboard','sharps_bin','mop_bucket','cardboard_box','stool','extinguisher']:
        b=model(name)
        if name=='wall_clock': b(0,.22,0,.45,.45,.08,7); b(0,.25,.05,.04,.23,.03,4,False)
        elif name=='terminal': b(0,.04,0,.6,.08,.4,4); b(0,.35,-.1,.65,.5,.13,10)
        elif name=='clipboard': b(0,.015,0,.25,.03,.36,7); b(0,.035,-.13,.1,.015,.06,4,False)
        elif name=='sharps_bin': b(0,.2,0,.3,.4,.3,11); b(0,.42,0,.32,.04,.32,6)
        elif name=='mop_bucket': b(0,.22,0,.5,.45,.45,6); b(.2,1,0,.035,1.7,.035,13)
        elif name=='cardboard_box': b(0,.25,0,.6,.5,.55,7); b(0,.51,0,.08,.02,.55,6,False)
        elif name=='stool': legs(b,.45,.45,.6); b(0,.65,0,.5,.1,.5,8)
        else: b(0,.3,0,.22,.6,.22,6); b(0,.66,0,.08,.14,.08,4); b(.12,.4,0,.04,.4,.04,15)
    for new,old in [('medical_bag','personal_bag'),('medicine_fridge','lab_fridge'),('tool_drawers','desk_drawers'),('shipping_crate','cold_chain_crate'),('security_locker','staff_locker')]:
        recipes[new]=[list(part) for part in recipes[old]]
        if new=='medical_bag':
            for part in recipes[new]: part[6]=3
        if new=='shipping_crate':
            for part in recipes[new]: part[6]=7
    for name,w,h,d,tile in [('weapon_box',1.4,.4,.5,4),('weapon_crate',1.8,.7,.65,13),('ammo_box',.65,.42,.42,6)]:
        b=model(name)
        b(0,h/2,0,w,h,d,tile)
        for x in [-w*.38,w*.38]: b(x,h/2,d*.5+.015,.08,h,.03,4,False)
        b(0,h+.03,0,w+.04,.06,d+.04,tile)
    recipes['storage_table']=[list(p) for p in recipes['packing_table'][:5]]
    recipes['clean_workbench']=[list(p) for p in recipes['instrument_bench'][:6]]
    b=model('pallet_rack')
    for x in [-4.8,0,4.8]:
        for z in [-1.35,1.35]:
            b(x,3.9,z,.16,7.8,.16,4)
            b(x,.08,z,.5,.16,.5,6)
        for y in [1.3,3.9,6.5]: b(x,y,0,.12,.12,2.7,4)
    for y in [.3,2.9,5.5]:
        for z in [-1.35,1.35]: b(0,y,z,9.6,.22,.15,6)
        b(0,y,0,9.6,.12,2.7,4)
        for index,x in enumerate([-3.5,-1.2,1.2,3.5]):
            b(x,y+.18,0,1.8,.22,2.2,13)
            h=1.25 if index%2 else 1.7
            b(x,y+.3+h/2,0,1.65,h,1.9,7 if index%2 else 9)
            b(x,y+.3+h/2,1,1.65,.06,.025,3,False)
            b(x,y+.65,1,.4,.25,.03,10,False)
    for name,tile in [('medkit',3),('infection_suppressant',12),('food',7),('tool',4),('salvage',13),('research_drive',10),('lab_electronics',10),('five_five_six',6),('medtac_keycard',9),('research_notes',7),('sealed_specimen',12),('sterile_lab_supplies',3),('personal_effects',14),('stanag_magazine',4)]:
        b=model('pickup_'+name)
        if name in ['infection_suppressant','sealed_specimen']: b(0,.12,0,.08,.24,.08,tile); b(0,.26,0,.09,.04,.09,6)
        elif name=='research_notes': b(0,.012,0,.24,.024,.32,7); b(0,.026,-.1,.16,.005,.04,4,False)
        elif name=='research_drive': b(0,.025,0,.13,.05,.09,4); b(.075,.025,0,.04,.025,.05,3)
        elif name=='lab_electronics': b(0,.012,0,.25,.024,.18,2); b(0,.035,0,.08,.03,.06,4)
        else:
            b(0,.07,0,.28,.14,.2,tile)
            b(0,.15,0,.1,.02,.2,3,False)
    target=ROOT/'resources/medtac'
    target.mkdir(parents=True,exist_ok=True)
    (target/'prop_recipes.json').write_text(json.dumps(recipes,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':
    atlas(); signs(); models()
