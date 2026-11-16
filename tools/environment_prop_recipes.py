"""Authored meter-scale prop recipes; compile with build_environment_props.gd.

Only the standard library is needed. The numbered catalog is the source of IDs
and variant names. Components describe construction, not randomly scattered voxels.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Model:
    def __init__(self, identity: int, variant: str, index: int):
        self.id, self.variant, self.index = identity, variant.lower(), index
        self.parts: list[dict] = []
        self.group = "body"
        self.pivot = [0, 0, 0]
        self.opening = "hinge"
        self.initial_open = False
        self.offset = (0, 0, 0)
        self.damaged = any(s in self.variant for s in (
            "broken", "damaged", "ruined", "destroyed", "shattered", "crashed",
            "smashed", "breached", "forced", "ruptured", "sabotaged", "collapsed"))
        self.worn = any(s in self.variant for s in (
            "rust", "worn", "abandoned", "faded", "weather", "dirty", "stained", "burn"))
        self.paint = "rust" if self.worn else "paint"

    def box(self, at, size, mat="steel", solid=False, rot=(0, 0, 0), name="frame"):
        assert min(size) > 0, (self.id, name, size)
        self.parts.append(dict(shape="box", at=[a+b for a,b in zip(at,self.offset)],
                               size=list(size), material=mat, collision=solid,
                               rotation=list(rot), group=self.group, component=name))

    def cyl(self, at, radius, length, mat="steel", axis=1, solid=False, sides=8, name="mechanism"):
        self.parts.append(dict(shape="cylinder", at=[a+b for a,b in zip(at,self.offset)],
                               radius=radius, length=length, material=mat,
                               axis=axis, sides=sides, collision=solid,
                               rotation=[0,0,0], group=self.group, component=name))

    def profile(self, points, depth, at=(0,0,0), mat="steel", solid=False, axis=2, name="profile"):
        self.parts.append(dict(shape="profile", points=points, depth=depth,
                               at=[a+b for a,b in zip(at,self.offset)], material=mat,
                               collision=solid, axis=axis, rotation=[0,0,0],
                               group=self.group, component=name))

    def beam(self, a, b, width=.06, mat="steel", solid=False, name="brace"):
        d = [b[i]-a[i] for i in range(3)]
        length = math.sqrt(sum(x*x for x in d))
        self.box([(a[i]+b[i])/2 for i in range(3)], (width,length,width), mat,
                 solid, (math.atan2(math.hypot(d[0],d[2]),d[1]), math.atan2(d[0],d[2]),0), name)

    def feet(self, w, d, h, mat="steel", width=.07, wheels=False):
        for x in [-w/2+width/2, w/2-width/2]:
            for z in [-d/2+width/2, d/2-width/2]:
                self.box((x,h/2,z),(width,h,width),mat,True,name="legs")
                if wheels: self.cyl((x,.08,z),.08,.065,"rubber",0,name="casters")

    def wheel(self, at, r=.32, axis=0):
        self.cyl(at,r,.18,"rubber",axis,True,12,"tire")
        shift = list(at); shift[axis] += .1 if at[axis]>=0 else -.1
        self.cyl(shift,r*.57,.025,"steel",axis,name="wheel_hub")
        shift[axis] += .018 if at[axis]>=0 else -.018
        self.cyl(shift,r*.21,.03,"rust",axis,name="axle_cap")

    def frame(self, w, h, depth=.09, mat="steel", at=(0,0,0), solid=True):
        x,y,z=at
        for side in [-1,1]: self.box((x+side*w/2,y+h/2,z),(.075,h,depth),mat,solid,name="uprights")
        for level in [y+.04,y+h-.04]: self.box((x,level,z),(w,.08,depth),mat,solid,name="crossrails")

    def screen(self, at, w=.46, h=.32, active=False):
        x,y,z=at
        self.box(at,(w,h,.1),self.paint,True,name="display_housing")
        self.box((x,y,z-.056),(w-.055,h-.055,.015),"glass",name="display")
        if active:
            for j in range(5):
                self.box((x-w*.32+j*w*.15,y+(.035 if j==2 else -.025),z-.066),
                         (w*.13,.018,.009),"light",name="screen_trace")
        self.box((x+w*.37,y-h*.4,z-.065),(.025,.018,.015),"red",name="power_button")

    def handle(self, at, w=.22, mat="steel", group=None):
        prev=self.group
        if group: self.group=group
        x,y,z=at
        for side in [-1,1]: self.box((x+side*w/2,y,z+.02),(.035,.035,.07),mat,name="handle_mount")
        self.box((x,y,z-.02),(w,.035,.035),mat,name="handle")
        self.group=prev

    def panel(self, at, size, mat="paint", kind="hinge", initially_open=False):
        self.pivot=[at[0]-size[0]/2,at[1]-size[1]/2,at[2]] if kind=="hinge" else [at[0],at[1],at[2]+size[2]/2]
        self.opening=kind; self.initial_open=initially_open
        prev=self.group; self.group="panel"
        self.box(at,size,mat,True,name="moving_panel")
        if kind=="lid": self.handle((at[0],at[1]+size[1]/2+.025,at[2]-size[2]*.34),min(.25,size[0]*.4))
        else: self.handle((at[0]+size[0]*.3,at[1],at[2]-.07),min(.2,size[0]*.3))
        self.group=prev

    def cabinet(self, w=.8,h=1.6,d=.5,mat=None,open=False,shelves=3,drawers=False):
        mat=mat or self.paint
        for x in [-w/2+.03,w/2-.03]: self.box((x,h/2,0),(.06,h,d),mat,True,name="case_sides")
        for y in [.035,h-.035]: self.box((0,y,0),(w,.07,d),mat,True,name="case_ends")
        self.box((0,h/2,d/2-.025),(w-.1,h-.1,.05),mat,True,name="case_back")
        for i in range(1,shelves+1): self.box((0,i*h/(shelves+1),0),(w-.12,.035,d-.08),"steel",True,name="shelves")
        if drawers:
            for i in range(shelves+1):
                y=(i+.5)*h/(shelves+1)
                if i==shelves:
                    self.panel((0,y,-d/2),(w-.1,h/(shelves+1)-.04,.06),mat,"drawer",open)
                    self.box((0,y-.08,-.04),(w-.15,.03,d-.12),"steel",True,name="drawer_bottom")
                else:
                    self.box((0,y,-d/2),(w-.1,h/(shelves+1)-.04,.06),mat,True,name="drawer_face")
                    self.handle((0,y,-d/2-.04),.2)
        else: self.panel((0,h/2,-d/2),(w-.1,h-.12,.065),mat,"hinge",open)
        for y in [h*.2,h*.8]: self.box((-w/2+.04,y,-d/2-.04),(.05,.11,.06),"steel",name="hinges")

    def chest(self,w=.8,h=.45,d=.45,mat="paint",open=False,ribs=True):
        self.cabinet(w,h,d,mat,False,0)
        self.parts=[p for p in self.parts if p["group"]!="panel"]
        self.box((0,h*.5,-d/2+.03),(w,.9*h,.06),mat,True,name="case_front")
        self.panel((0,h+.02,0),(w+.035,.065,d+.035),mat,"lid",open)
        for x in [-w*.35,w*.35]:
            self.box((x,h*.65,-d/2-.04),(.075,.11,.04),"steel",name="latches")
            if ribs: self.box((x,h/2,0),(.045,h+.03,d+.07),"wood" if mat=="wood" else "steel",name="reinforcement_bands")
        self.handle((0,h*.55,-d/2-.07),min(.25,w*.3))

    def shelf(self,w=1.4,h=1.9,d=.55,loaded=False,mat="steel",levels=4):
        self.feet(w,d,h,mat,.065)
        for i in range(levels):
            y=.12+i*(h-.2)/(levels-1)
            self.box((0,y,0),(w,.045,d),mat,True,name="shelves")
            if loaded and i<levels-1:
                for j in range(3):
                    self.box((-w*.32+j*w*.3,y+.16,0),(w*.23,.28,d*.7),"wood" if j%2 else "medical",name="stored_cartons")
        self.beam((-w*.45,.2,d*.46),(w*.45,h-.1,d*.46),.045,mat,name="back_brace")

    def table(self,w=1.4,d=.7,h=.76,mat="wood",clutter=False):
        self.feet(w-.1,d-.1,h-.08,"steel" if mat!="wood" else "wood",.08)
        self.box((0,h-.04,0),(w,.08,d),mat,True,name="worktop")
        for z in [-d*.35,d*.35]: self.box((0,h-.16,z),(w-.15,.12,.05),"steel",True,name="apron")
        if clutter:
            self.box((-.3,h+.025,-.05),(.34,.05,.25),"medical",name="papers")
            self.cyl((.35,h+.075,0),.06,.15,"rust",name="cup")

    def pipe(self,a,b,r=.09,mat="steel",solid=True):
        d=[b[i]-a[i] for i in range(3)]; length=math.sqrt(sum(x*x for x in d))
        at=[(a[i]+b[i])/2 for i in range(3)]
        self.cyl(at,r,length,mat,1,solid,8,"pipe")
        self.parts[-1]["rotation"]=[math.atan2(math.hypot(d[0],d[2]),d[1]),math.atan2(d[0],d[2]),0]

    def books(self,at,count=7):
        for i in range(count):
            self.box((at[0]+i*.065,at[1]+.13,at[2]),(.055,.26+(i%3)*.025,.16),["wood","paint","red"][i%3],name="books")

    def damage_edges(self):
        # Wear follows exposed seams: remove trim and expose a supporting edge.
        if self.worn:
            for p in self.parts:
                if p["component"] in ["hinges","latches","reinforcement_bands","back_brace"]: p["material"]="rust"
        if self.damaged:
            for i,p in enumerate(self.parts):
                if p["component"] in ["display","lamps","handle","stored_cartons","books","slats","glazing"]:
                    self.parts.pop(i)
                    break

    def authored_condition(self):
        n,v=self.id,self.variant
        if n==12 and "burned" in v:
            for p in self.parts:
                if p["component"]=="refuse": p["material"]="rubber";p["size"][1]*=.5
        if n==14:
            for j,p in enumerate(self.parts):
                if "brick" in v or ("mixed" in v and j%2):
                    p["material"]="red";p["size"]=[.28,.12,.14]
        if n==20:
            for j,p in enumerate(self.parts):
                p["size"][1]=.045 if j%2 else .12
                p["material"]="rubber" if "burned" in v else "rust" if "rusty" in v else "steel"
                if "rusty" in v: p["size"][0]*=.8
        if n==24 and "bent" in v:
            for p in self.parts:
                if p["component"]=="shutter_slats" and p["at"][1]<1: p["at"][2]-=.15;p["rotation"][1]=.08
        if n==55 and "cracked" in v: self.beam((-.2,.78,-.23),(.08,.72,-.23),.016,"rubber",name="basin_crack")
        if n==63 and self.damaged: self.box((.35,.88,-.2),(.24,.04,.2),"rust",name="failed_regulator_cover")
        if n==73 and "broken" in v:
            self.parts=[p for p in self.parts if p["component"]!="wheel_spokes"]
            self.box((.2,.06,0),(.24,.06,.12),"rust",name="broken_valve_stem")
        if n==81 and self.damaged:
            self.parts=[p for p in self.parts if not(p["component"]=="insulator_discs" and p["at"][0]>0 and p["at"][1]>1.4)]
        if n==85 and "loaded" in v: self.pipe((0,.08,-.4),(.8,.04,-.5),.035,"rubber",False)
        if n==88 and self.damaged: self.box((.3,.03,-.4),(.35,.04,.25),"oil",name="pump_oil_leak")
        if n==89 and "broken" in v:
            self.parts=[p for p in self.parts if not(p["component"]=="filter_canisters" and p["at"][0]>0)]
            self.box((.5,.06,0),(.16,.12,.35),"medical",name="broken_filter")
        if n==91 and self.damaged: self.box((.2,.15,-.2),(.18,.04,.25),"contamination",name="chemical_residue")
        if n==92 and "rusty" in v:
            self.box((.1,.2,-.2),(.2,.08,.06),"rust",name="corroded_lower_seam")
        if n==96 and "abandoned" in v: self.box((.15,.98,.25),(.6,.04,.9),"cloth_dark",name="discarded_blanket")
        if n==102 and "used" in v: self.box((.12,1.02,-.2),(.4,.025,.55),"red",name="surgical_stain")
        if n==105 and "ruined" in v:
            self.parts=[p for p in self.parts if p["component"]!="eyepiece"]
            self.box((-.4,.95,-.2),(.3,.05,.25),"glass",name="broken_instrument_tray")
        if n==110 and "emergency" in v: self.box((0,1.9,0),(.22,.05,.08),"red",name="emergency_status_bar")
        if n==128 and "covered" in v: self.box((0,.15,0),(1.8,.3,1.3),"cloth_dark",True,name="covered_supplies")
        if n in [137,154] and "mixed" in v:
            self.box((-.1,.3,-.2),(.4,.05,.3),"medical",name="discarded_paper")
        if n==172 and "sealed" in v: self.box((0,.72,0),(.065,.025,.8),"warning",name="tamper_seal")
        if n==175 and "emergency" in v:
            self.box((.24,.12,-.23),(.07,.1,.04),"warning",name="quick_release_tab")
        if n==175 and "medtac" in v:
            self.group="panel";self.box((.15,.31,0),(.14,.04,.12),"glass",name="temperature_sensor");self.group="body"
        if n==176 and "looted" in v:
            self.box((.15,.15,-.1),(.15,.025,.1),"medical",name="discarded_blister_wrap")
        if n in [177,188] and "secure" in v:
            self.box((.2,.2,-.28),(.14,.12,.06),"rubber",name="combination_lock")
        if n==188 and "industrial" in v:
            for x in [-.3,.3]: self.box((x,.1,0),(.06,.25,.5),"steel",name="case_corner_rails")
        if n==198 and "tactical" in v:
            self.group="panel"
            for x in [-.4,.4]: self.box((x,.24,0),(.06,.04,.4),"cloth_dark",name="tactical_webbing")
            self.group="body"
        if n==200 and "military" in v:
            self.box((0,1.45,-.7),(.5,.12,.04),"warning",name="military_stencil_plate")


def street(m: Model):
    n,v,k=m.id,m.variant,m.index
    if n in [1,15]:
        w=2.8 if n==1 else 1.2
        count=2 if "stacked" in v else 1
        for j in range(count):
            if "collapsed" in v:
                for x in [-.85,0,.85]: m.box((x,.18,0),(.7,.36,.55),"concrete",True,rot=(0,.15*x,0),name="broken_barrier")
                for x in [-.55,.55]: m.beam((x,.15,0),(x+.35,.42,0),.035,"rust")
            else:
                m.profile([[-.42,0],[.42,0],[.42,.18],[.2,.65],[.15,1.05],[-.15,1.05],[-.2,.65],[-.42,.18]],w,(0,j*1.05,0),"concrete",True,0,"jersey_profile")
                for x in [-w*.3,w*.3]: m.box((x,.95+j*1.05,-.158),(.27,.12,.025),"warning",name="reflectors")
                if "crack" in v: m.beam((-.25,.25,-.31),(.1,.9,-.165),.024,"rubber",name="fracture")
                if "reinforced" in v:
                    for x in [-w*.35,w*.35]: m.box((x,.55,0),(.12,1.1,.88),"steel",True,name="reinforcing_straps")
    elif n==2:
        m.box((0,.035,0),(.42,.07,.42),"rubber",True,name="base")
        h=.27 if "crushed" in v else .68
        for j in range(5): m.box((.035*j if "crushed" in v else 0,.07+(j+.5)*h/5,0),(.29-j*.05,h/5,.29-j*.05),"medical" if j in [2,3] else "warning",name="tapered_cone")
        if "faded" in v: m.box((.1,.15,-.15),(.11,.07,.035),"rubber",name="split_base")
    elif n in [3,4,16]:
        w,h=(2.4,1.0) if n==3 else (3.2,.85) if n==4 else (2.6,1.9)
        for x in [-w*.45,w*.45]:
            m.box((x,.06,0),(.5,.12,.75),"concrete" if n==16 else "steel",True,name="feet")
            m.box((x,h/2,0),(.08,h,.08),m.paint,True,name="posts")
        if n==4:
            for j in range(5):
                x=-w/2+(j+.5)*w/5
                z=.25*(x/w)**2*8 if "curved" in v else 0
                if "broken" in v and j==4: continue
                m.profile([[-.16,-.15],[0,-.11],[.16,-.15],[.16,.15],[0,.11],[-.16,.15]],w/5,(x,.68,z),m.paint,True,0,"corrugated_guardrail")
            if "overgrown" in v:
                for x in [-1,-.5,.2]: m.box((x,.3,-.1),(.4,.6,.16),"contamination",name="vines")
        elif n==3:
            mat="wood" if "improvised" in v else m.paint
            for y in [.5,.82]:
                m.box((0,y,0),(w,.16,.08),mat,True,rot=(0,0,.12 if "bent" in v else 0),name="rails")
                for x in [-.9,-.3,.3,.9]: m.box((x,y,-.048),(.2,.12,.02),"warning",name="warning_marks")
        else:
            for x in range(12):
                if "torn" in v and x>8: continue
                m.box((-1.2+x*.21,h/2,0),(.025,h-.18,.025),"rust",name="wire_mesh")
            for y in range(8): m.box((0,.2+y*.21,0),(w-.2,.025,.025),"rust",name="wire_mesh")
            if "bent" in v: m.beam((-1,.1,-.4),(1,1.7,0),.065,"steel",True)
        if "fallen" in v: tip(m,(math.pi/2,0,0))
    elif n in [5,6,7]:
        h=5.5 if n==5 else 3.8 if n==6 else 2.3
        m.box((0,.1,0),(.45,.2,.45),"concrete",True,name="footing")
        m.box((0,h/2,0),(.12,h,.12),m.paint,True,name="pole")
        if n==5:
            m.beam((0,h-.15,0),(1,h,-.1),.1,m.paint,name="lamp_arm")
            m.box((1,h,-.1),(.6,.16,.28),"steel",name="lamp_housing")
            if "broken" not in v: m.box((1,h-.09,-.1),(.47,.025,.22),"light",name="diffuser")
            if "flickering" in v: m.box((.91,h-.1,-.1),(.05,.02,.22),"rubber",name="failed_lamp_segment")
        elif n==6:
            m.box((0,h-.6,-.16),(.38,1.12,.25),"rubber",True,name="signal_housing")
            for i,mat in enumerate(["red","warning","contamination"]):
                if "shattered" in v and i==2: continue
                m.cyl((0,h-.25-i*.32,-.305),.12,.035,mat,2,name="signal_lens")
                m.box((0,h-.1-i*.32,-.37),(.3,.055,.2),"steel",name="signal_hood")
            if "hanging" in v:
                for p in m.parts:
                    if p["component"].startswith("signal"): p["rotation"][2]=.26
        else:
            w=.9 if "warning" in v else 1.5
            if "warning" in v: m.profile([[0,0],[.55,.55],[0,1.1],[-.55,.55]],.07,(0,h-.8,-.1),"warning",name="diamond_sign")
            else:
                m.box((0,h-.4,-.1),(w,.65,.07),"paint",True,name="sign_board")
                for i in range(3): m.box((-.15,h-.2-i*.17,-.143),(.7-i*.12,.045,.012),"medical",name="direction_text")
                m.beam((.43,h-.52,-.15),(.62,h-.35,-.15),.05,"medical",name="arrow")
            if "faded" in v: m.box((-.3,h-.4,-.15),(.3,.11,.02),"rust",name="flaked_sign_edge")
            if "vandal" in v: m.beam((-.45,h-.6,-.15),(.4,h-.2,-.15),.08,"red",name="painted_slash")
        if "fallen" in v: tip(m,(math.pi/2,0,0))
    elif n==8:
        for x in [-1.4,1.4]:
            for z in [0,.7]: m.box((x,1.25,z),(.1,2.5,.1),"steel",True,name="shelter_columns")
        m.box((0,2.5,.25),(3.2,.16,1.5),m.paint,True,name="shelter_roof")
        if "shattered" not in v: m.box((0,1.4,.72),(2.7,1.8,.04),"glass",True,name="shelter_glazing")
        m.box((0,.5,.4),(2.3,.1,.45),"wood",True,name="bench")
        for x in [-.8,.8]: m.box((x,.25,.4),(.1,.5,.3),"steel",True,name="bench_supports")
        if "fortified" in v:
            for y in [.8,1.2,1.6]: m.box((0,y,-.1),(2.8,.24,.06),"wood",True,name="defensive_boards")
    elif n in [9,10]:
        if n==9:
            m.box((0,.1,0),(.6,.2,.5),"steel",True,name="plinth")
            m.cabinet(.55,1.05,.45,open="closed" not in v,shelves=1)
            m.box((0,.9,-.25),(.4,.2,.03),"glass",name="display_window")
            if "empty" not in v:
                m.group="contents"; m.box((0,.35,-.05),(.32,.16,.24),"medical",name="newspapers"); m.group="body"
        else:
            m.box((0,.035,0),(.22,.07,.22),"steel",True,name="meter_footing")
            m.box((0,.55,0),(.075,1.1,.075),"steel",True,name="meter_post")
            m.profile([[-.18,0],[.18,0],[.22,.32],[.14,.48],[-.14,.48],[-.22,.32]],.18,(0,1.05,0),m.paint,True,name="meter_head")
            if "stripped" not in v:
                m.box((0,1.36,-.1),(.24,.12,.02),"glass",name="meter_dial")
                m.box((.08,1.18,-.1),(.015,.08,.02),"rubber",name="coin_slot")
            if "damaged" in v: m.box((-.16,1.3,-.11),(.08,.06,.04),"rust",name="broken_housing")
    elif n in [11,78,117]:
        pallet(m, loaded=any(s in v for s in ["loaded","cargo","sealed","opened"]),stacked="stacked" in v,broken=any(s in v for s in ["broken","collapsed"]))
        if n==117:
            for j in range(4 if "scattered" not in v else 2):
                m.offset=(-.3+(j%2)*.6,.18+(j//2)*.28,0)
                m.chest(.5,.25,.55,"paint",open="opened" in v,ribs=False)
            m.offset=(0,0,0)
    elif n in [12,13,14,20,137,154]:
        debris(m,"rubber" if n==13 else "wood" if n==154 else "concrete" if n==14 else "rust",large="large" in v)
        if n==12:
            for j in range(3): m.box((-.4+j*.4,.15,-.2+j*.15),(.25,.15,.3),"medical" if "household" in v else "steel",rot=(.1,j*.4,.1),name="refuse")
    elif n==17:
        m.cyl((0,.04,0),.53,.08,"steel",solid=False,sides=12,name="rim")
        m.cyl((0,.085,0),.47,.015,"rubber",name="opening")
        if "missing" not in v:
            m.cyl((.3 if "ajar" in v else 0,.11,0),.46,.045,m.paint,name="cover")
            for x in [-.25,-.1,.1,.25]: m.box((x+(.3 if "ajar" in v else 0),.14,0),(.035,.015,.55),"rust",name="cover_ribs")
    elif n==18:
        for x in [-.42,.42]: m.box((x,.05,0),(.06,.1,.5),"steel",name="grate_frame")
        for z in [-.25,.25]: m.box((0,.05,z),(.9,.1,.06),"steel",name="grate_frame")
        for j in range(9):
            if "broken" in v and j in [4,5]: continue
            m.box((-.36+j*.09,.05,0),(.035,.08,.44),"steel",name="grate_bars")
        if "clogged" in v: m.box((.18,.1,.1),(.35,.04,.24),"dirt",name="leaves_in_grate")
    elif n==19:
        m.feet(.65,.95,.25,wheels=True)
        m.box((0,.3,0),(.58,.04,.8),"steel",True,name="basket_floor")
        for x in [-.3,.3]:
            for z in [-.36,-.18,0,.18,.36]: m.beam((x,.3,z),(x*1.2,.85,z),.025,"steel",name="basket_wire")
            for y in [.4,.6,.84]: m.box((x,y,0),(.025,.025,.8),"steel",name="basket_wire")
        for z in [-.4,.4]: m.box((0,.85,z),(.65,.035,.035),"steel",name="basket_rim")
        m.beam((-.3,.3,.4),(-.3,1.0,.6)); m.beam((.3,.3,.4),(.3,1,.6))
        m.box((0,1,.6),(.65,.05,.06),"rubber",name="push_handle")
        if "loaded" in v: m.box((0,.52,0),(.45,.4,.5),"wood",name="salvaged_carton")
        if "damaged" in v: m.beam((-.3,.84,-.4),(.05,.7,-.45),.035,"rust")
        if "overturned" in v: tip(m,(0,0,math.pi/2))


def pallet(m,loaded=False,stacked=False,broken=False):
    for level in range(3 if stacked else 1):
        y=level*.16
        for x in [-.5,0,.5]: m.box((x,y+.07,0),(.12,.14,.95),"wood",True,name="pallet_stringers")
        for j in range(6):
            if broken and j in [2,3]: continue
            m.box((-.5+j*.2,y+.165,0),(.15,.05,1.0),"wood",True,name="pallet_deck")
    if loaded:
        for x in [-.28,.28]:
            m.box((x,.5,0),(.5,.6,.8),"wood",True,name="cargo_cartons")
            m.box((x,.81,0),(.06,.025,.81),"medical",name="packing_tape")


def debris(m,mat="concrete",large=False):
    count=11 if large else 7
    for j in range(count):
        angle=j*2.4; r=.12+(j%4)*.17
        x,z=math.cos(angle)*r,math.sin(angle)*r
        h=.14+(j%3)*.11
        if mat=="rubber":
            m.profile([[-.2,0],[.18,0],[.25,.13],[.15,.33],[-.1,.36],[-.25,.15]],.35,(x,0,z),mat,name="filled_bag")
            m.box((x,.37,z),(.07,.07,.07),"rubber",name="tied_bag_neck")
        elif m.id==14:
            y=.02+(j//4)*.1
            m.profile([[-.18,0],[.15,0],[.2,.06],[.08,.18],[-.1,.15],[-.21,.08]],.28,(x,y,z),"red" if "brick" in m.variant or ("mixed" in m.variant and j%2) else "concrete",large,name="chipped_masonry")
            m.parts[-1]["rotation"][1]=angle
        else:
            m.box((x,h/2,z),(.3+(j%2)*.1,h,.35),mat,large,rot=(0,angle,0),name="debris_fragments")
    if "torn" in m.variant: m.box((.4,.05,-.3),(.35,.04,.2),"medical",name="spilled_refuse")
    if "wet" in m.variant: m.box((0,.012,0),(1.4,.025,1.1),"glass",name="pooled_water")
    if m.id==14 and "brick" not in m.variant:
        m.beam((-.2,.13,0),(.4,.33,0),.025,"rust",name="exposed_rebar")
    if m.id==12:
        m.box((-.2,.25,-.1),(.5,.04,.38),"cardboard",name="carton_bottom")
        for x in [-.43,.03]: m.box((x,.39,-.1),(.035,.28,.38),"cardboard",name="carton_sides")
        m.box((-.2,.55,.1),(.5,.04,.3),"cardboard",rot=(.45,0,0),name="carton_flap")
        m.cyl((.38,.15,-.3),.12,.26,"rubber",axis=2,name="discarded_can")


def tip(m,rotation):
    # Apply an assembly transform in the compiler, retaining matching collision.
    for p in m.parts: p["assembly_rotation"]=list(rotation)


def exterior(m: Model):
    n,v=m.id,m.variant
    if n in [21,22,23,24,25,37,39]:
        w,h=(2.8,2.6) if n in [23,24] else (1.4,1.3) if n in [25,39] else (1.05,2.15) if n in [21,22] else (2.3,1.9)
        mat="wood" if n==22 or "wood" in v else m.paint
        m.frame(w,h,.12,"wood" if n==22 else "steel")
        if n in [23,24]:
            bottom=1.25 if "partially" in v else 1.7 if "breached" in v or "destroyed" in v else .08
            for j in range(int((h-bottom)/.13)):
                m.box((0,bottom+.065+j*.13,0),(w-.1,.11,.07),mat,True,name="shutter_slats")
            m.box((0,h+.08,0),(w+.2,.22,.28),"steel",True,name="roller_housing")
        elif n in [25,39]:
            if n==25 and "intact" in v: m.box((0,h*.5,0),(w-.12,h-.12,.035),"glass",True,name="glazing")
            m.box((0,h/2,-.035),(.05,h,.05),"steel",True,name="mullion")
            m.box((0,h/2,-.035),(w,.05,.05),"steel",True,name="transom")
            if n==39 or "boarded" in v or "barred" in v:
                if "sheet" in v: m.box((0,h/2,-.12),(w-.1,h-.1,.06),"rust",True,name="metal_boarding")
                else:
                    for j in range(5): m.box((-.55+j*.27,h/2,-.11),(.1,h,.07),"wood" if "wood" in v or "boarded" in v else "steel",True,name="window_barricade")
                    if "welded" in v: m.box((0,h/2,-.17),(w,.08,.06),"rust",True,name="welded_brace")
        elif n==37:
            m.panel((0,h/2,0),(w-.15,h-.15,.06),mat,"hinge","open" in v)
            for j in range(10): m.box((-.95+j*.21,h/2,-.05),(.025,h-.2,.025),"steel",name="gate_mesh")
            if "locked" in v: m.cyl((.85,h*.5,-.08),.07,.05,"rust",2,name="padlock")
        else:
            m.panel((0,h/2,0),(w-.13,h-.12,.075),mat,"hinge",False)
            m.box((w*.29,1.03,-.08),(.1,.2,.03),"steel",name="lock_plate")
            if n==22:
                for j in range(5): m.box((-.36+j*.18,h/2,-.045),(.015,h-.15,.015),"rubber",name="plank_seams")
            if "reinforced" in v or "boarded" in v:
                for y in [.6,1.3,1.8]: m.box((0,y,-.12),(w,.16,.08),"steel" if n==21 else "wood",True,name="door_braces")
            if m.damaged: m.beam((-.4,.5,-.07),(.2,1.6,-.07),.05,"rust",name="split_panel")
    elif n in [26,27]:
        w,h,d=(.95,.65,.45) if n==26 else (1.8,1.1,1.4) if "large" not in v else (2.8,1.5,1.8)
        m.box((0,h/2,0),(w,h,d),m.paint,True,name="housing")
        if "stripped" not in v:
            fan(m,(w*.2,h*.5,-d/2-.04),min(h,w)*.36,False)
            for j in range(6): m.box((-w*.35,h*.16+j*h*.11,-d/2-.035),(w*.3,.025,.03),"steel",name="cooling_louvers")
        else:
            m.box((0,h/2,-d/2-.03),(w*.7,h*.65,.04),"rubber",name="empty_access_bay")
            for x in [-.2,.2]: m.pipe((x,.1,-.28),(x,.5,-.28),.025,"rust",False)
        if n==26:
            for x in [-w*.35,w*.35]: m.box((x,-.05,0),(.08,.1,d+.15),"steel",True,name="wall_brackets")
        else:
            m.box((0,.05,0),(w+.2,.1,d+.2),"steel",True,name="roof_curb")
            m.box((w*.2,h+.12,0),(.6,.24,.55),"steel",True,name="duct_outlet")
            if "broken" in v: m.box((-.5,h+.1,0),(.45,.05,.4),"rust",rot=(0,0,.25),name="detached_panel")
    elif n in [28,29]:
        if n==28:
            m.box((0,.04,0),(2,.08,.24),"steel",name="gutter_trough")
            for z in [-.13,.13]: m.box((0,.12,z),(2,.16,.025),m.paint,name="gutter_rim")
            for x in [-.8,.8]: m.box((x,.04,.16),(.06,.2,.16),"rust",name="gutter_bracket")
            if "detached" in v: tip(m,(0,0,.25))
            if "bent" in v: m.box((.85,.15,0),(.3,.04,.23),"rust",rot=(0,0,.2),name="bent_lip")
        else:
            m.pipe((0,.2,0),(0,2.8,0),.09,m.paint)
            m.pipe((0,.2,0),(0,.1,-.35),.09,m.paint)
            for y in [.7,2.2]: m.box((0,y,.1),(.25,.08,.12),"steel",name="wall_clamps")
            if "leaking" in v: m.box((0,.1,-.35),(.35,.025,.45),"glass",name="water_pool")
            if "broken" in v: m.parts=[p for p in m.parts if p["component"]!="pipe" or p["at"][1]<1]
    elif n in [30,31]:
        if n==30:
            h=3.6 if "extended" in v else 1.9
            for x in [-.32,.32]: m.box((x,h/2,0),(.07,h,.08),"steel",True,name="ladder_rails")
            for j in range(int(h/.28)): m.box((0,.18+j*.28,0),(.6,.045,.08),"steel",True,name="ladder_rungs")
            for y in [.2,h-.2]: m.box((0,y,.16),(.8,.06,.3),"rust",name="standoffs")
            if "folded" in v: m.box((0,1,.08),(.75,.16,.06),"rust",name="fold_latch")
        else:
            mat="concrete" if "concrete" in v else "steel"
            for j in range(10):
                if "ruined" in v and j in [5,6]: continue
                m.box((0,(j+1)*.2,-j*.28),(1.2,.12,.28),mat,True,name="stair_treads")
                for x in [-.62,.62]: m.box((x,(j+1)*.2+.5,-j*.28),(.05,1,.05),"steel",True,name="railing_posts")
            for x in [-.62,.62]:
                m.beam((x,.2,.2),(x,2.1,-2.7),.12,"steel",True,"stringers")
                m.beam((x,1.2,.2),(x,3.1,-2.7),.06,"steel",True,"handrails")
    elif n in [32,40]:
        w,d,h=(2.8,1.3,2.3) if n==32 else (3.6,2.2,2.8)
        mat="cloth" if "fabric" in v or "torn" in v else "concrete" if "concrete" in v else "steel"
        m.box((0,h,-d/2),(w,.1,d),mat,True,rot=(.12,0,0),name="canopy_roof")
        for x in [-w*.45,w*.45]:
            m.beam((x,h,.05),(x,h-.65,-d*.8),.07,"steel",True,"canopy_braces")
            if n==40: m.box((x,h/2,-d*.8),(.13,h,.13),mat,True,name="entrance_columns")
        if "torn" in v or "damaged" in v: m.box((w*.32,h-.18,-d*.8),(.35,.3,.05),"cloth",rot=(0,0,.2),name="hanging_edge")
    elif n in [33,34,35]:
        if n==33:
            m.box((0,.4,0),(2,.8,.15),m.paint,True,name="sign_casing")
            for j in range(6): m.box((-.7+j*.27,.4,-.09),(.14,.4,.035),"light" if "lit" in v else "medical",name="raised_letters")
            for x in [-.8,.8]: m.box((x,.9,0),(.06,.25,.07),"steel",name="sign_hangers")
            if "hanging" in v: tip(m,(0,0,.18))
            if "broken" in v: m.parts=[p for p in m.parts if not(p["component"]=="raised_letters" and p["at"][0]>.3)]
        elif n==34:
            m.box((0,.12,.1),(.12,.24,.1),"steel",True,name="mounting_plate")
            m.beam((0,.12,0),(.25,.2,-.25),.06,"steel",name="camera_bracket")
            m.box((.25,.3,-.32),(.22,.2,.45),m.paint,name="camera_body")
            m.box((.25,.43,-.36),(.28,.04,.5),"steel",name="weather_hood")
            if "smashed" not in v: m.cyl((.25,.3,-.56),.065,.03,"glass",2,name="lens")
            if "disabled" in v: m.beam((.25,.25,-.18),(.1,.05,-.25),.025,"rubber",name="severed_cable")
        else:
            m.cabinet(.65,.85,.22,open="open" in v,shelves=1)
            for j in range(4): m.box((-.17+j*.11,.5,-.04),(.07,.24,.08),"rubber",name="breakers")
            m.box((0,.75,-.16),(.12,.08,.02),"warning",name="voltage_label")
    elif n==36:
        m.frame(2.6,2.1,.08)
        for j in range(12):
            if "torn" in v and j>7: continue
            m.beam((-1.2+j*.2,.1,0),(-.2+j*.2,2,0),.016,"steel",name="chain_link")
            m.beam((-.2+j*.2,.1,0),(-1.2+j*.2,2,0),.016,"steel",name="chain_link")
        if "barbed" in v:
            for y in [2.2,2.35]: m.box((0,y,0),(2.6,.025,.025),"rust",name="barbed_wire")
        if "patched" in v: m.box((.6,.7,-.035),(.75,.9,.025),"rust",True,name="sheet_patch")
    elif n==38:
        m.box((0,.04,0),(.65,.08,.65),"steel",True,name="dish_base")
        m.beam((0,.08,0),(0,.65,.2),.1,"steel",True,"dish_mount")
        for j in range(4): m.cyl((0,.7+j*.035,.13-j*.04),.5-j*.1,.05,"medical",2,name="stepped_dish")
        m.beam((0,.4,-.05),(0,.65,-.5),.05,"steel",name="feed_arm")
        m.box((0,.65,-.5),(.12,.12,.16),"rubber",name="feedhorn")
        if "tilted" in v: tip(m,(0,0,.35))
        if "destroyed" in v: m.parts=[p for p in m.parts if not(p["component"]=="stepped_dish" and p["radius"]<.3)]


def fan(m,at,r=.25,stand=False):
    x,y,z=at
    m.cyl(at,r,.1,"steel",2,name="fan_rim")
    m.cyl((x,y,z-.06),r*.88,.03,"rubber",2,name="fan_recess")
    for j in range(4):
        a=j*math.pi/2+.3
        m.box((x+math.cos(a)*r*.4,y+math.sin(a)*r*.4,z-.085),(r*.7,.08,.025),"steel",rot=(0,0,a),name="fan_blades")
    m.cyl((x,y,z-.11),r*.17,.06,"steel",2,name="fan_hub")
    if stand:
        m.box((x,.05,z),(.5,.1,.4),"steel",True,name="fan_stand")
        m.box((x,y/2,z),(.07,y,.07),"steel",True,name="fan_pedestal")


def interior(m: Model):
    n,v=m.id,m.variant
    if n in [41,46,58,61,114,132]:
        w=2 if "large" in v else 1.4
        m.table(w,.75,.78,"steel" if n==61 else "wood",any(s in v for s in ["cluttered","staffed","upgraded"]))
        if n in [41,114]:
            m.offset=(.45,0,0); m.cabinet(.42,.69,.57,shelves=2,drawers=True,open="looted" in v or "ransacked" in v); m.offset=(0,0,0)
        if n in [58,114] or "mechanical" in v:
            if "stripped" not in v:
                m.screen((0,1.12,-.16),.55,.38,"destroyed" not in v)
                m.box((0,.89,-.1),(.06,.22,.07),"steel",name="monitor_stand")
                m.box((0,.81,-.1),(.32,.035,.24),"steel",name="monitor_foot")
                m.box((0,.84,.19),(.5,.04,.15),"rubber",name="keyboard")
                for j in range(6): m.box((-.2+j*.08,.866,.2),(.05,.01,.1),"medical",name="key_rows")
            m.box((.5,.25,-.1),(.25,.5,.48),"rubber",True,name="tower")
            if "gaming" in v: m.box((.635,.3,-.1),(.02,.28,.32),"glass",name="tower_window")
        if n in [61,132]:
            m.box((-.4,.9,0),(.22,.24,.2),"steel",True,name="vise")
            m.cyl((-.4,.91,.14),.04,.3,"steel",2,name="vise_screw")
            m.box((0,.12,0),(w-.15,.08,.6),"wood",True,name="lower_shelf")
            m.panel((.3,.57,-.28),(.5,.18,.06),"wood","drawer","empty" in v)
            if "upgraded" in v:
                m.box((0,1.17,-.35),(1.3,.7,.06),"wood",True,name="pegboard")
                for x in [-.4,0,.4]: m.box((x,1.2,-.4),(.06,.3,.05),"steel",name="hanging_tools")
        if m.damaged:
            m.parts=[p for p in m.parts if not(p["component"]=="legs" and p["at"][0]<0 and p["at"][2]<0)]
            m.beam((-.55,0,-.25),(-.35,.7,-.25),.09,"wood",True,"splinted_leg")
    elif n in [42,47]:
        if n==42:
            for j in range(5):
                a=j*math.tau/5; m.beam((0,.12,0),(.32*math.cos(a),.09,.32*math.sin(a)),.06,"steel")
                m.cyl((.32*math.cos(a),.07,.32*math.sin(a)),.06,.04,"rubber",0,name="casters")
            m.cyl((0,.3,0),.045,.4,"steel",solid=True)
        else: m.feet(.43,.45,.45,"wood" if "wood" in v else "steel",.055)
        m.box((0,.48,0),(.5,.1,.5),"cloth" if n==42 else "wood",True,name="seat")
        for x in [-.2,.2]: m.box((x,.73,.2),(.045,.65,.045),"steel",True,name="back_posts")
        m.box((0,.86,.22),(.5,.36,.07),"cloth" if n==42 else "wood",True,name="backrest")
        if "worn" in v: m.box((-.15,.537,-.1),(.18,.015,.16),"cloth_dark",name="seat_repair")
        if "overturned" in v: tip(m,(math.pi/2,0,0))
        if m.damaged: m.parts=[p for p in m.parts if not(p["component"]=="back_posts" and p["at"][0]>0)]
    elif n in [43,51,52,53]:
        w,h,d=(.5,1.35,.6) if n==43 else (1.2,1.9,.6) if n==51 else (.9,.72,.36) if n==52 else (.8,1.75,.72)
        mat="wood" if n in [51,52] else "medical" if n==53 else m.paint
        m.cabinet(w,h,d,mat,"open" in v,3,n==43)
        if n==53:
            m.box((0,h*.75,-d/2-.045),(w-.12,.025,.02),"rubber",name="freezer_seal")
            for j in range(6): m.box((0,.1+j*.08,d/2+.015),(w*.8,.025,.025),"rubber",name="condenser_coil")
            if "stripped" in v: m.parts=[p for p in m.parts if p["component"] not in ["shelves","moving_panel","handle"]]
        if n==52:
            m.box((0,h+.025,0),(w+.04,.05,d+.05),"concrete",True,name="countertop")
            if "wall" in v: m.box((0,h*.8,d*.5+.04),(w*.8,.08,.06),"steel",name="wall_mount")
        if "locked" in v: m.cyl((w*.3,h*.55,-d/2-.08),.04,.04,"steel",2,name="lock")
    elif n in [44,45]:
        m.shelf(1.2,1.8,.4,"stocked" in v,"wood" if n==44 else m.paint)
        if n==44 and "stocked" in v:
            for y in [.16,.68,1.2]: m.books((-.48,y,-.08),12)
        if m.damaged:
            if "collapsed" in v: tip(m,(0,0,math.pi/2))
            else: m.beam((-.55,.2,-.18),(-.36,1.4,-.18),.06,"rust")
    elif n==48:
        m.box((0,.24,0),(2.0,.32,.8),"cloth_dark",True,name="sofa_base")
        for x in [-.65,0,.65]: m.box((x,.48,-.05),(.61,.2,.7),"cloth",True,name="seat_cushions")
        m.box((0,.73,.34),(1.9,.7,.18),"cloth",True,name="sofa_back")
        for x in [-.98,.98]: m.box((x,.55,0),(.18,.55,.85),"cloth_dark",True,name="sofa_arms")
        m.feet(1.8,.65,.12,"wood")
        if "torn" in v: m.box((-.5,.588,-.08),(.22,.02,.27),"dirt",name="exposed_stuffing")
        if "stained" in v: m.box((.48,.589,0),(.4,.015,.32),"dirt",name="water_stain")
        if "barricaded" in v:
            for y in [.7,1]: m.box((0,y,-.5),(2.1,.16,.09),"wood",True,name="plank_barricade")
    elif n in [49,50,96,97,102,126]:
        bed(m,n)
    elif n in [54,55,56]:
        if n==54:
            m.box((0,.43,0),(.65,.86,.63),"medical",True,name="oven_body")
            m.panel((0,.4,-.33),(.54,.5,.06),"steel","lid")
            m.box((0,.43,-.37),(.4,.26,.02),"glass",name="oven_window")
            for x in [-.16,.16]:
                for z in [-.16,.16]: m.cyl((x,.88,z),.1,.025,"rubber",name="burners")
            for x in [-.2,-.07,.07,.2]: m.cyl((x,.79,-.34),.035,.03,"steel",2,name="oven_knobs")
        elif n==55:
            m.box((0,.36,.1),(.18,.72,.22),"medical",True,name="sink_pedestal")
            basin(m,(0,.76,0),.65,.45)
            if "detached" in v: m.parts=[p for p in m.parts if p["component"]!="sink_pedestal"]; tip(m,(.2,0,0))
        else:
            m.box((0,.18,.05),(.28,.36,.42),"medical",True,name="toilet_plinth")
            m.cyl((0,.39,-.08),.25,.2,"medical",solid=True,sides=12,name="bowl")
            m.cyl((0,.5,-.08),.18,.025,"rubber",name="bowl_opening")
            m.box((0,.65,.25),(.46,.55,.2),"medical",True,name="cistern")
            m.box((0,.95,.25),(.5,.06,.23),"medical",name="cistern_lid")
            m.box((.16,.8,.13),(.08,.04,.04),"steel",name="flush_lever")
        if "dirty" in v: m.box((0,.12,0),(.32,.03,.25),"dirt",name="limescale")
        if m.damaged: m.beam((-.18,.5,-.3),(.15,.7,-.22),.025,"rubber",name="ceramic_fracture")
    elif n==57:
        if "crt" in v:
            m.box((0,.33,.06),(.7,.6,.46),m.paint,True,name="crt_case")
            m.screen((-.02,.35,-.2),.58,.42)
            for x in [-.18,.18]: m.box((x,.02,.1),(.12,.04,.28),"rubber",True,name="tv_feet")
        else:
            m.screen((0,.48,0),1.05,.62)
            m.box((0,.16,.03),(.08,.32,.08),"steel",True,name="tv_stand")
            m.box((0,.035,0),(.55,.07,.3),"rubber",True,name="tv_foot")
        if "shattered" in v:
            for a in [-.6,.8]: m.beam((0,.4,-.065),(.4*a,.65,-.065),.016,"medical",name="screen_cracks")
    elif n==59:
        m.cyl((0,.3,0),.3,.07,"steel",2,name="clock_rim")
        m.cyl((0,.3,-.04),.265,.02,"medical",2,name="clock_face")
        for j in range(12):
            a=j*math.tau/12; m.box((math.sin(a)*.22,.3+math.cos(a)*.22,-.056),(.025,.035,.012),"rubber",rot=(0,0,-a),name="hour_marks")
        m.beam((0,.3,-.065),(.14,.42,-.065),.025,"rubber",name="minute_hand")
        m.beam((0,.3,-.07),(-.1,.36,-.07),.03,"rubber",name="hour_hand")
        if "stopped" in v: m.box((.15,.16,-.06),(.08,.04,.025),"rust",name="loose_hand")
        if "broken" in v: m.beam((-.15,.1,-.07),(.18,.5,-.07),.015,"glass",name="cracked_face")
    elif n in [60,107]:
        curtain="curtain" in v or n==107
        w=2.0
        m.frame(w,1.9,.065)
        for x in [-1,1]: m.box((x,.03,0),(.1,.06,.65),"steel",True,name="divider_feet")
        if curtain:
            width=.65 if "open" in v else 1.9
            for j in range(12):
                if "torn" in v and j in [7,8]: continue
                m.box((-1+(j+.5)*width/12,1.05,.03 if j%2 else -.03),(width/12+.015,1.55,.065),"cloth",False,name="curtain_folds")
        else: m.box((0,1,0),(1.9,1.65,.09),"wood" if "improvised" in v else "cloth_dark",True,name="partition_panel")


def basin(m,at,w=.65,d=.45):
    x,y,z=at
    m.box((x,y-.09,z),(w,.05,d),"medical",True,name="basin_bottom")
    for side in [-1,1]:
        m.box((x+side*w*.46,y,z),(.055,.18,d),"medical",True,name="basin_sides")
        m.box((x,y,z+side*d*.45),(w,.18,.055),"medical",True,name="basin_ends")
    m.pipe((x,y+.08,z+d*.3),(x,y+.32,z+d*.3),.025,"steel",False)
    m.pipe((x,y+.32,z+d*.3),(x,y+.32,z),.025,"steel",False)


def bed(m,n):
    v=m.variant
    w=1.55 if "double" in v else .9; d=2.05
    if n==50:
        m.box((0,.1,0),(w,.2,d),"cloth",True,name="mattress")
        for z in [-.8,-.4,0,.4,.8]: m.box((0,.207,z),(w*.94,.012,.025),"cloth_dark",name="mattress_seams")
        if "dirty" in v or "blood" in v: m.box((.12,.216,-.3),(.5,.012,.55),"red" if "blood" in v else "dirt",name="stain")
        return
    h=.8 if n in [96,97,102] else .5
    m.feet(w,d,h-.05,"wood" if n==126 else "steel",.06,wheels=n in [96,97,102])
    m.box((0,h,0),(w,.1,d),"steel" if n==102 else "wood",True,name="bed_deck")
    if n in [96,97,102,126] and "basic" not in v:
        m.box((0,h+.12,0),(w-.08,.16,d-.08),"medical" if n==102 else "cloth",True,name="mattress")
        if n!=102: m.box((0,h+.24,-.7),(w*.75,.1,.4),"medical",name="pillow")
    if n in [49,96]:
        for z in [-d/2,d/2]:
            m.frame(w,.5,.07,"steel",(0,h,z))
            for x in [-w*.25,0,w*.25]: m.box((x,h+.25,z),(.035,.42,.035),"steel",name="headboard_bars")
    if n==96:
        for x in [-w/2,w/2]: m.box((x,h+.3,0),(.055,.04,1.1),"steel",True,name="safety_rails")
        if "bloody" in v: m.box((.1,h+.21,-.2),(.45,.025,.65),"red",name="bloodstain")
        if "improvised" in v: m.box((0,h+.2,.5),(w,.05,.6),"cloth_dark",name="replacement_blanket")
    if n==97:
        m.beam((-.35,.15,-.6),(-.35,h,.6),.06,"steel",True,"folding_frame")
        m.beam((.35,.15,.6),(.35,h,-.6),.06,"steel",True,"folding_frame")
        if "folded" in v: tip(m,(math.pi/2,0,0))
    if n==102:
        m.box((0,h+.28,-.72),(.55,.12,.4),"medical",True,name="head_support")
        m.box((0,h*.45,0),(.4,h*.7,.55),"steel",True,name="hydraulic_pedestal")
    if m.damaged: m.beam((-.4,h,-.8),(-.25,h+.18,-.5),.05,"rust",name="bent_rail")


def industrial(m: Model):
    n,v=m.id,m.variant
    if n in [61,132]: interior(m); return
    if n==62:
        m.cabinet(.85,.78,.5,open="open" in v,shelves=3,drawers=True)
        for x in [-.34,.34]:
            for z in [-.18,.18]: m.wheel((x,.09,z),.09)
        m.box((.48,.75,0),(.12,.06,.45),"steel",name="trolley_handle")
        if "looted" not in v: m.box((0,.81,0),(.5,.04,.3),"rubber",name="tool_liner")
    elif n==63:
        m.table(1.4,.7,.85,"steel")
        m.box((-.35,1.05,0),(.5,.4,.4),m.paint,True,name="welder_housing")
        for y in [.94,1.03,1.12]: m.box((-.35,y,-.21),(.35,.025,.02),"rubber",name="welder_vents")
        m.cyl((-.47,1.2,-.23),.04,.025,"rubber",2,name="current_dial")
        if "dismantled" not in v:
            m.cyl((.48,.7,.15),.16,1.25,"paint",solid=True,name="gas_cylinder")
            m.cyl((.48,1.4,.15),.035,.15,"steel",name="cylinder_valve")
            m.pipe((-.1,.93,-.2),(.3,.86,-.2),.02,"rubber",False)
        else: m.box((.35,.88,.1),(.38,.05,.3),"steel",name="removed_cover")
    elif n in [64,65,66]:
        if n==64:
            m.feet(1.9,.65,.85,"paint",.2)
            m.box((0,.9,0),(2,.2,.65),"steel",True,name="lathe_bed")
            for z in [-.18,.18]: m.box((0,1.04,z),(1.7,.06,.08),"steel",name="guideways")
            m.box((-.7,1.25,0),(.5,.65,.65),m.paint,True,name="headstock")
            m.cyl((-.36,1.35,0),.2,.18,"steel",0,name="chuck")
            m.cyl((0,1.35,0),.065,.65,"steel",0,name="workpiece")
            m.box((.55,1.16,0),(.3,.28,.5),m.paint,True,name="tailstock")
            m.box((.1,1.13,-.2),(.42,.18,.4),"steel",True,name="carriage")
            m.cyl((.1,1.07,-.47),.13,.05,"rubber",2,name="feed_handwheel")
        elif n==65:
            m.box((0,.06,0),(.65,.12,.85),"steel",True,name="drill_base")
            m.cyl((0,.8,.25),.07,1.5,"steel",solid=True,name="column")
            m.box((0,.85,0),(.6,.08,.55),"steel",True,name="drill_table")
            m.box((0,1.48,.02),(.38,.35,.65),m.paint,True,name="drill_head")
            m.cyl((0,1.15,-.2),.045,.35,"steel",name="spindle")
            if "stripped" not in v: m.cyl((0,.96,-.2),.016,.2,"steel",name="drill_bit")
            for y in [1.32,1.55]: m.beam((.2,1.42,-.1),(.48,y,-.1),.025,"steel",name="feed_lever")
        else:
            w,h= (1.3,2.0) if "large" not in v else (2.5,3.1)
            for x in [-w/2,w/2]:
                m.box((x,h/2,0),(.2,h,.65),m.paint,True,name="press_columns")
                m.box((x,.07,0),(.45,.14,.95),"steel",True,name="press_feet")
            m.box((0,h-.1,0),(w+.2,.25,.65),m.paint,True,name="crosshead")
            m.box((0,.65,0),(w,.15,.65),"steel",True,name="press_bed")
            m.cyl((0,h-.5,0),.15,.65,"steel",solid=True,name="hydraulic_ram")
            m.box((0,h-.85,0),(w*.55,.16,.5),"steel",True,name="ram_plate")
            m.pipe((w*.45,.5,.3),(w*.45,h-.25,.3),.025,"rubber",False)
        if m.damaged:
            m.box((.25,.35,-.35),(.4,.06,.3),"rust",True,rot=(0,.3,.15),name="fallen_guard")
    elif n==67:
        m.feet(2.4,.8,.65,"steel",.08)
        for z in [-.43,.43]: m.box((0,.72,z),(2.5,.16,.075),m.paint,True,name="conveyor_rails")
        for j in range(14):
            if "damaged" in v and j in [7,8]: continue
            m.cyl((-1.15+j*.175,.74,0),.065,.8,"steel",2,True,name="rollers")
        m.box((.8,.55,-.56),(.4,.25,.25),"steel",name="drive_motor")
        if "inclined" in v: tip(m,(0,0,.18))
        if "corner" in v:
            m.offset=(1.1,0,-.8); m.feet(.8,.9,.65)
            m.box((0,.74,0),(.8,.08,.9),"rubber",True,name="transfer_belt"); m.offset=(0,0,0)
    elif n in [68,69,84,88,89,94,95]:
        machine(m,n)
    elif n in [70,71,80,90,91,92]:
        tank(m,n)
    elif n in [72,73,93]:
        r=.18 if n!=93 else .28
        if n==73:
            m.pipe((0,0,0),(0,1.1,0),.1,"steel")
            m.box((0,.55,0),(.35,.3,.28),m.paint,True,name="valve_body")
            m.cyl((0,.55,-.25),.18,.045,"rust",2,name="valve_wheel")
            m.cyl((0,.55,-.28),.125,.05,"rubber",2,name="wheel_recess")
            for j in range(4):
                a=j*math.pi/2; m.beam((0,.55,-.32),(.16*math.cos(a),.55+.16*math.sin(a),-.32),.03,"steel",name="wheel_spokes")
            if "manual" in v: m.box((.15,.62,-.23),(.4,.04,.08),"red",name="valve_lever")
            if "motorized" in v: m.box((.25,.65,0),(.28,.3,.3),"paint",True,name="valve_actuator")
        else:
            m.pipe((0,r,0),(0,r,1.6),r,"steel")
            if "elbow" in v or "bend" in v: m.pipe((0,r,1.6),(1,r,1.6),r,"steel")
            if "junction" in v or "branch" in v: m.pipe((-.8,r,.8),(.8,r,.8),r,"steel")
            for z in [.06,1.54]:
                m.cyl((0,r,z),r*1.25,.08,"rust",2,name="flanges")
                for x in [-r*.85,r*.85]: m.box((x,r,z-.05),(.035,.035,.025),"steel",name="flange_bolts")
            if m.damaged: m.box((.17,r+.05,.8),(.2,.09,.18),"rust",rot=(0,.3,.3),name="split_seam")
    elif n==74:
        m.box((0,.5,0),(1.6,1,.65),m.paint,True,name="console_base")
        m.box((0,1.05,-.05),(1.65,.13,.8),"steel",True,rot=(.2,0,0),name="sloped_control_deck")
        for x in [-.4,.4]: m.screen((x,1.36,.17),.55,.35,"active" in v)
        for x in [-.55,-.25,.05,.35,.55]: m.cyl((x,1.16,-.27),.04,.035,"red" if x<0 else "warning",name="control_buttons")
        m.box((0,.45,-.34),(1.3,.7,.03),"steel",name="service_panel")
    elif n==75:
        fan(m,(0,.65,-.05),.48,"floor" in v)
        m.frame(1.1,1.2,.12)
        if "wall" in v: m.box((0,.6,.12),(1.15,1.25,.08),"steel",True,name="wall_flange")
        if "broken" in v: m.parts=[p for p in m.parts if not(p["component"]=="fan_blades" and p["at"][0]>0)]
    elif n==76:
        length=2.8 if "lowered" in v else 1.1
        m.cyl((0,length/2+.55,0),.035,length,"rubber",name="hoist_cable")
        m.box((0,.57,0),(.42,.42,.2),"warning",True,name="pulley_block")
        for x in [-.13,.13]: m.cyl((x,.6,0),.14,.06,"steel",0,name="sheaves")
        m.profile([[-.08,.5],[.08,.5],[.08,.18],[.24,.14],[.3,.28],[.32,.12],[.18,0],[-.04,.04],[-.12,.2]],.12,mat="steel",solid=True,name="crane_hook")
        if "damaged" in v: m.box((-.12,.55,-.12),(.14,.14,.025),"rust",name="block_repair")
    elif n==77:
        length=2.2 if "long" in v else 1.1
        for j in range(int(length/.14)):
            axis=j%2; at=(0,.1+j*.14,0)
            if axis==0: m.frame(.13,.2,.025,"rust" if "rust" in v else "steel",at,False)
            else:
                for z in [-.065,.065]: m.box((0,at[1]+.1,z),(.025,.2,.025),"steel",name="chain_link")
                for y in [at[1],at[1]+.2]: m.box((0,y,0),(.025,.025,.13),"steel",name="chain_link")
    elif n in [78,117]: street(m)
    elif n==79:
        m.shelf(3.2,2.8,1.1,"loaded" in v,"rust" if m.damaged else "steel",3)
        if "damaged" in v: m.beam((-1.5,0,-.5),(-1.2,1.2,-.5),.1,"rust",True,"bent_upright")


def machine(m,n):
    v=m.variant
    if n in [68,84]:
        big="large" in v or "industrial" in v
        w,h,d=(1.8,1.35,.9) if big else (.85,.65,.55)
        for x in [-w*.52,w*.52]:
            for z in [-d*.5,d*.5]: m.box((x,h/2,z),(.065,h,.065),"steel",True,name="protective_frame")
        for z in [-d*.5,d*.5]: m.box((0,h-.02,z),(w+.1,.06,.065),"steel",name="carry_rails")
        m.box((0,h*.48,0),(w*.8,h*.64,d*.85),m.paint,True,name="engine_housing")
        m.cyl((w*.2,h*.55,-d*.46),h*.22,.05,"rubber",2,name="generator_end")
        for j in range(5): m.box((-w*.25,h*.3+j*h*.07,-d*.46),(w*.3,.022,.025),"steel",name="engine_louvers")
        m.box((0,h*.84,0),(w*.65,h*.16,d*.7),"paint",True,name="fuel_tank")
        m.cyl((0,h*.95,0),.055,.045,"rubber",name="fuel_cap")
        m.pipe((w*.3,h*.7,d*.3),(w*.3,h*1.2,d*.3),.04,"rust",False)
        if "improvised" in v: m.box((-.3,.7,0),(.25,.2,.2),"wood",True,name="replacement_fuel_feed")
        if "ruined" in v: m.box((w*.1,.12,-d*.7),(.5,.08,.4),"rust",True,name="fallen_engine_guard")
    elif n==69:
        r=.22 if "portable" in v else .35
        m.cyl((0,r+.12,0),r,1.0,"paint",0,True,12,"pressure_tank")
        m.feet(.7,.4,.2)
        m.box((0,r*2+.25,0),(.45,.3,.35),"steel",True,name="compressor_motor")
        for x in [-.15,0,.15]: m.box((x,r*2+.42,0),(.05,.08,.3),"steel",name="cooling_fins")
        m.cyl((.28,r*2+.2,-.08),.07,.035,"medical",2,name="pressure_gauge")
        if "portable" in v:
            for x in [-.4,.4]: m.wheel((x,.12,.13),.12)
            m.beam((-.5,.3,0),(-.5,.9,0),.045,"steel",name="pull_handle")
        if "leaking" in v: m.pipe((.45,.35,0),(.5,.03,-.3),.022,"rubber",False)
    elif n==88:
        m.box((0,.06,0),(.9,.12,.7),"concrete",True,name="pump_foundation")
        m.cyl((-.2,.35,0),.22,.35,"paint",0,True,name="impeller_housing")
        m.cyl((.25,.35,0),.18,.5,"steel",0,True,name="pump_motor")
        for j in range(5): m.box((.1+j*.07,.5,0),(.025,.06,.2),"steel",name="motor_fins")
        m.pipe((-.35,.35,0),(-.65,.35,0),.095)
        m.pipe((-.2,.5,0),(-.2,.9,0),.095)
        if "large" in v:
            for p in m.parts:
                p["at"]=[x*1.5 for x in p["at"]]
                if "size" in p: p["size"]=[x*1.5 for x in p["size"]]
                if "radius" in p: p["radius"]*=1.5; p["length"]*=1.5
    elif n==89:
        m.frame(1.2,1.7,.5)
        for x in [-.35,0,.35]:
            m.cyl((x,.85,0),.13,1.2,"medical",solid=True,name="filter_canisters")
            m.pipe((x,1.45,0),(x,1.65,0),.04)
        m.pipe((-.4,1.65,0),(.4,1.65,0),.05)
        m.box((.65,.9,0),(.28,.4,.3),m.paint,True,name="filter_controls")
        if "improvised" in v: m.box((0,1.75,0),(.8,.18,.6),"wood",True,name="gravity_feed_tray")
    elif n==94:
        m.shelf(1.5,1.45,.6,False,"steel",3)
        for y in [.3,.95]:
            for x in [-.5,0,.5]:
                m.box((x,y,0),(.4,.32,.42),"rubber",True,name="battery_cells")
                for z in [-.12,.12]: m.box((x,y+.18,z),(.06,.04,.06),"steel",name="terminals")
            m.box((0,y+.22,.12),(1.2,.03,.035),"red",name="bus_bar")
        if "damaged" in v: m.box((-.4,.2,-.35),(.35,.05,.28),"dirt",name="electrolyte_tray")
        if "functional" in v: m.box((.6,1.35,-.32),(.04,.04,.02),"light",name="charge_indicator")
    elif n==95:
        m.cabinet(.85,1.8,.65,shelves=4,open="stripped" in v)
        for y in [.45,.8,1.15,1.5]:
            m.box((0,y,-.35),(.68,.24,.045),"rubber",name="radio_modules")
            m.cyl((.23,y,-.39),.04,.025,"steel",2,name="tuning_dial")
            if "active" in v: m.box((-.15,y,-.38),(.16,.06,.02),"light",name="radio_readout")
        m.pipe((.3,1.8,.1),(.3,2.5,.1),.02,"steel",False)


def tank(m,n):
    v=m.variant
    r,h=(.3,.88) if n in [90,91] else (.18,.6) if n==92 and "small" in v else (.28,1.1) if n==92 else (.65,1.9) if n in [71,80] else (.7,2.1)
    horizontal="horizontal" in v
    mat="plastic" if n==91 else "medical" if n==92 else m.paint
    if "crushed" in v: h*=.55
    m.cyl((0,r+.15,0) if horizontal else (0,h/2,0),r,h,mat,0 if horizontal else 1,True,12,"tank_shell")
    for y in [.12,h-.12]:
        if horizontal: m.cyl((y-h/2,r+.15,0),r+.035,.045,"steel",0,name="tank_bands")
        else: m.cyl((0,y,0),r+.025,.045,"steel" if n!=91 else mat,name="tank_bands")
    if n not in [90,91]:
        m.feet(r*1.2,r*1.2,.18,"steel",.08)
        m.cyl((0,h+.06,0),r*.22,.12,"steel",name="valve_neck")
        m.box((0,h+.14,0),(.24,.035,.06),"red",name="valve_handle")
    else:
        m.cyl((r*.45,h+.02,0),.045,.035,"rubber",name="bung")
    if n in [71,80]:
        m.pipe((r*.7,h*.25,0),(r*1.7,h*.25,0),.075)
        m.box((0,h*.65,-r-.015),(.3,.25,.025),"warning",name="hazard_plate")
    if "reinforced" in v:
        for x in [-r*.65,r*.65]: m.box((x,h/2,0),(.06,h+.1,r*1.8),"steel",True,name="tank_cage")
    if any(s in v for s in ["leak","contaminated","ruptured"]):
        m.box((r*.65,.015,-.3),(.65,.03,.85),"contamination" if n in [71,91] else "glass",name="spill")
    if "ruptured" in v: m.box((r,.4,-.05),(.25,.5,.04),"rust",rot=(0,0,.4),name="peeled_shell")
    if n==91 and "yellow" in v: m.box((0,h*.6,-r-.02),(.25,.2,.025),"warning",name="chemical_label")


def utility(m: Model):
    n,v=m.id,m.variant
    if n in [81,82,83]:
        if n==81:
            w=1.1 if "small" in v else 1.9
            m.box((0,.08,0),(w+.25,.16,1.0),"concrete",True,name="transformer_pad")
            m.box((0,.65,0),(w,1.1,.8),m.paint,True,name="transformer_tank")
            for x in [-w/2-.07,w/2+.07]:
                for z in [-.28,-.14,0,.14,.28]: m.box((x,.65,z),(.12,.85,.04),"steel",True,name="cooling_fins")
            for x in [-w*.3,0,w*.3]:
                for j in range(4): m.cyl((x,1.25+j*.085,0),.075 if j%2 else .1,.08,"medical",name="insulator_discs")
                m.cyl((x,1.6,0),.03,.12,"steel",name="high_voltage_terminal")
        else:
            w,h,d=(1.2,1.9,.45) if n==82 else (.7,1.05,.2)
            m.cabinet(w,h,d,open="open" in v or "exposed" in v,shelves=3)
            for y in [.25,.65,1.0] if n==82 else [.25,.55,.8]:
                for x in [-w*.25,0,w*.25]: m.box((x,y,-d*.1),(.12,.18,.12),"rubber",name="circuit_breakers")
            if "exposed" in v: m.pipe((-.2,.1,-.08),(-.2,.8,-.08),.025,"red",False)
    elif n in [84,88,89,94,95]: machine(m,n)
    elif n==85:
        mat="steel" if "metal" in v else "wood"
        for x in [-.38,.38]: m.cyl((x,.53,0),.53,.1,mat,0,True,12,"spool_flange")
        m.cyl((0,.53,0),.18,.7,"wood",0,True,name="spool_core")
        if "empty" not in v:
            for x in [-.27,-.18,-.09,0,.09,.18,.27]: m.cyl((x,.53,0),.39,.075,"rubber",0,name="wound_cable")
        m.cyl((-.44,.53,0),.065,.02,"rubber",0,name="spool_bore")
    elif n==86:
        for j in range(3):
            r=.2+j*.065
            for k in range(12):
                a=k*math.tau/12; b=(k+1)*math.tau/12
                m.beam((r*math.cos(a),.035,r*math.sin(a)),(r*math.cos(b),.035,r*math.sin(b)),.035,"rubber",name="cable_coil")
        if "loose" in v: m.pipe((.35,.03,0),(.85,.03,-.2),.018,"rubber",False)
        if "hanging" in v: tip(m,(math.pi/2,0,0))
    elif n==87:
        mat="wood" if "wooden" in v else "concrete"
        m.box((0,3,0),(.2,6,.2),mat,True,name="utility_pole")
        for y in [5.2,5.65]:
            m.box((0,y,0),(1.7,.12,.14),"wood",name="crossarm")
            for x in [-.65,.65]: m.cyl((x,y+.16,0),.075,.2,"medical",name="insulators")
        if "fallen" in v: tip(m,(0,0,math.pi/2))
    elif n in [90,91,92]: tank(m,n)
    elif n==93: industrial(m)


def medical(m: Model):
    n,v=m.id,m.variant
    if n in [96,97,102]: bed(m,n)
    elif n==98:
        for j in range(4):
            a=j*math.pi/2; m.beam((0,.08,0),(.3*math.cos(a),.06,.3*math.sin(a)),.045,"steel",name="iv_base")
        m.pipe((0,.08,0),(0,1.9,0),.02)
        m.box((0,1.9,0),(.5,.03,.03),"steel",name="bag_hooks")
        if "equipped" in v:
            for x in [-.17,.17]: m.box((x,1.65,0),(.15,.26,.055),"medical",name="iv_bag")
            m.pipe((-.17,.5,.03),(-.17,1.5,.03),.008,"rubber",False)
        if "bent" in v: tip(m,(0,0,.18))
    elif n in [99,103]:
        if n==99:
            m.feet(.7,.5,.9,"steel",.04,True)
            for y in [.2,.65,.9]: m.box((0,y,0),(.72,.045,.52),"medical",True,name="cart_shelves")
            if "stocked" in v:
                for x in [-.2,0,.2]: m.cyl((x,1.01,0),.045,.17,"medical",name="supply_bottles")
            if "overturned" in v: tip(m,(0,0,math.pi/2))
        else:
            m.box((0,.025,0),(.7,.05,.4),"steel",name="tray")
            for z in [-.2,.2]: m.box((0,.065,z),(.7,.08,.025),"steel",name="tray_rim")
            for j in range(5): m.box((-.25+j*.12,.065,0),(.02,.025,.26),"rust" if "contaminated" in v else "steel",rot=(0,.35*j if "scattered" in v else 0,0),name="instruments")
    elif n in [100,110]:
        if n==110:
            m.box((0,.06,0),(.7,.12,.6),"steel",True,name="terminal_base")
            m.box((0,.75,.08),(.22,1.4,.3),"medical",True,name="terminal_pedestal")
            m.screen((0,1.55,0),.7,.52,"active" in v or "emergency" in v)
            m.box((0,1.15,-.16),(.6,.06,.4),"medical",True,rot=(.18,0,0),name="input_deck")
            m.box((.28,1.05,-.16),(.07,.15,.08),"red",name="emergency_switch")
        else:
            m.box((0,.03,0),(.42,.06,.3),"medical",True,name="monitor_base")
            m.box((0,.12,0),(.08,.2,.08),"steel",name="monitor_stand")
            m.screen((0,.4,0),.55,.4,"working" in v or "flicker" in v)
            if "flicker" in v: m.box((0,.42,-.07),(.47,.035,.01),"rubber",name="failed_scanline")
    elif n==101:
        m.frame(1.15,1.45,.6)
        for y in [.15,.85]: m.box((0,y,0),(1.2,.07,.6),"steel",True,name="cylinder_retainer")
        count=4 if "full" in v else 2 if "partial" in v else 0
        for j in range(count):
            x=-.42+j*.28; m.cyl((x,.65,0),.115,1.1,"medical",solid=True,name="oxygen_cylinders")
            m.cyl((x,1.25,0),.03,.14,"steel",name="oxygen_valves")
    elif n==104:
        m.cabinet(.85,1.9,.7,"medical","open" in v,4)
        m.group="panel"; m.box((0,1,-.41),(.6,1.3,.025),"glass",name="insulated_viewing_window"); m.group="body"
        m.box((.25,1.76,-.39),(.16,.08,.02),"rubber" if "powerless" in v else "light",name="temperature_readout")
    elif n==105:
        m.table(1.8,.8,.9,"medical")
        m.box((0,.25,0),(1.7,.45,.65),"medical",True,name="bench_cupboards")
        if "empty" not in v:
            m.box((-.4,1.05,0),(.25,.2,.3),"steel",name="microscope_base")
            m.beam((-.4,1.1,.1),(-.4,1.5,0),.07,"medical",name="microscope_arm")
            m.cyl((-.4,1.5,-.05),.045,.2,"rubber",2,name="eyepiece")
            m.box((.45,1.05,0),(.4,.3,.4),"medical",name="centrifuge")
            m.cyl((.45,1.23,0),.17,.05,"glass",name="centrifuge_lid")
    elif n==106:
        m.box((0,.03,0),(.65,.06,.3),"steel",name="sample_rack_base")
        for y in [.14,.3]: m.box((0,y,0),(.65,.035,.3),"steel",name="sample_rack_grid")
        if "empty" not in v:
            for x in [-.24,-.12,0,.12,.24]:
                for z in [-.07,.07]: m.cyl((x,.25,z),.035,.35,"glass" if "shattered" not in v else "rubber",name="sample_tubes")
    elif n==107: interior(m)
    elif n==108:
        m.box((0,.33,0),(.5,.66,.45),"plastic",True,name="waste_bin")
        m.panel((0,.7,0),(.55,.06,.5),"warning","lid","overflowing" in v)
        m.box((0,.42,-.23),(.2,.18,.02),"warning",name="biohazard_label")
        if "overflowing" in v:
            m.group="contents"
            for x in [-.12,.12]: m.box((x,.75,0),(.2,.25,.25),"rubber",name="waste_bags")
            m.group="body"
        if "tipped" in v: tip(m,(0,0,math.pi/2))
    elif n==109:
        m.box((0,.035,0),(1.15,.07,1.0),"steel",True,name="drain_platform")
        m.frame(1.1,2.3,.09)
        m.pipe((0,2.25,0),(0,2.25,-.4),.035)
        m.cyl((0,2.2,-.4),.14,.07,"medical",name="shower_head")
        m.box((.4,1.2,0),(.18,.3,.12),"warning",name="shower_valve")
        for z in [-.3,-.15,0,.15,.3]: m.box((0,.079,z),(.95,.018,.025),"rubber",name="drain_slots")
        if "leaking" in v: m.box((0,.08,-.2),(.7,.02,.5),"glass",name="standing_water")
        if "broken" in v: m.beam((0,2.25,0),(.25,2.02,-.4),.04,"rust",name="failed_head_mount")


def security(m: Model):
    n,v=m.id,m.variant
    if n in [111,112]:
        if n==112:
            m.profile([[-.5,0],[.5,0],[.4,.4],[.22,1.25],[-.22,1.25],[-.4,.4]],2.2,(0,0,0),"concrete",True,0,"defensive_profile")
            if "double" in v: m.box((0,.18,.8),(2.2,.36,.6),"concrete",True,name="second_course")
            if "damaged" in v: m.beam((-.6,.8,-.35),(.4,.4,-.43),.03,"rust",name="exposed_rebar")
        else:
            layers=5 if "high" in v else 3
            for y in range(layers):
                for j in range(4):
                    if "breached" in v and j in [1,2]: continue
                    x=-.9+j*.58+(y%2)*.15
                    m.profile([[-.27,.03],[-.22,0],[.22,0],[.28,.05],[.25,.18],[-.23,.18]],.4,(x,y*.18,0),"cloth_dark",True,name="sandbags")
                if "corner" in v:
                    for j in range(2): m.box((1.15,.09+y*.18,.35+j*.4),(.42,.18,.48),"cloth_dark",True,name="corner_sandbags")
    elif n==113:
        m.box((0,.08,0),(2.0,.16,1.7),"concrete",True,name="booth_floor")
        for x in [-.95,.95]:
            m.box((x,1.2,0),(.1,2.4,1.65),m.paint,True,name="booth_sidewalls")
            m.box((x*1.06,1.65,0),(.025,.65,1.2),"glass",name="booth_windows")
        m.box((0,1.2,.8),(2,2.4,.1),m.paint,True,name="booth_back")
        m.box((0,.6,-.8),(2,1.2,.1),m.paint,True,name="counter_wall")
        m.box((0,1.22,-.8),(2.1,.08,.4),"steel",True,name="inspection_counter")
        m.box((0,2.45,0),(2.3,.15,2),"steel",True,name="booth_roof")
        m.offset=(.45,0,.3); m.cabinet(.55,.9,.45,shelves=1); m.offset=(0,0,0)
        if "fortified" in v:
            for x in [-.7,0,.7]: m.box((x,1.8,-.8),(.06,1.2,.06),"steel",True,name="security_bars")
        if "abandoned" in v: m.box((.3,1.28,-.7),(.4,.05,.3),"medical",name="abandoned_records")
    elif n==114: interior(m)
    elif n==115:
        for x in [-.48,.48]: m.box((x,1.1,0),(.17,2.2,.45),"medical",True,name="detector_columns")
        m.box((0,2.2,0),(1.1,.18,.45),"medical",True,name="detector_header")
        m.box((0,2.21,-.24),(.3,.08,.02),"rubber" if "disabled" in v else "light",name="detector_display")
        if "destroyed" in v: m.parts=[p for p in m.parts if p["component"]!="detector_header"]
    elif n==116:
        m.shelf(1.4,1.65,.45,False,"steel",2)
        for x in [-.5,-.15,.2,.5]:
            m.box((x,.3,-.1),(.09,.14,.2),"wood",name="stock_cradle")
            if "stocked" in v:
                m.box((x,.75,0),(.08,.8,.1),"steel",name="rifle_receiver")
                m.box((x,.37,.02),(.13,.3,.12),"wood",name="rifle_stock")
                m.cyl((x,1.3,0),.02,.45,"steel",name="rifle_barrel")
        if "looted" in v: m.box((.2,.2,-.2),(.35,.03,.16),"cloth",name="discarded_sling")
    elif n==117: street(m)
    elif n==118:
        m.box((0,.18,0),(.52,.36,.24),"paint",True,name="field_radio_body")
        m.box((-.12,.22,-.13),(.18,.12,.02),"light" if "active" in v else "glass",name="tuner_display")
        for x in [.1,.2]: m.cyl((x,.15,-.14),.035,.03,"rubber",2,name="radio_knobs")
        m.pipe((-.2,.35,0),(-.2,1.1,0),.012,"steel",False)
        m.handle((0,.4,0),.28)
        if "damaged" in v: m.box((-.2,.12,-.15),(.13,.08,.025),"rust",name="cracked_radio_face")
    elif n in [119,120]:
        if n==119:
            for j in range(3):
                a=j*math.tau/3; m.beam((0,.5,0),(.6*math.cos(a),.04,.6*math.sin(a)),.055,"steel",True,"tripod")
            m.pipe((0,.4,0),(0,2.1,0),.045)
            for x in [-.35,.35]:
                m.box((x,2.12,0),(.55,.35,.15),"steel",name="floodlight_housing")
                m.box((x,2.12,-.085),(.46,.27,.025),"glass" if "damaged" in v else "light",name="floodlight_lens")
            if "folded" in v: tip(m,(math.pi/2,0,0))
        else:
            m.box((0,.1,0),(.65,.2,.5),"steel",True,name="searchlight_base")
            for x in [-.3,.3]: m.box((x,.45,0),(.06,.65,.12),"steel",name="searchlight_yoke")
            m.cyl((0,.55,0),.28,.48,"paint",2,True,name="searchlight_barrel")
            m.cyl((0,.55,-.25),.24,.03,"glass" if "broken" in v else "light",2,name="searchlight_lens")
            if "detached" in v: tip(m,(0,0,.5))
    elif n==121:
        for j in range(7):
            x=-1.2+j*.4
            for k in range(8):
                a=k*math.tau/8; b=(k+1)*math.tau/8
                m.beam((x,.38+.35*math.cos(a),.35*math.sin(a)),(x+.05,.38+.35*math.cos(b),.35*math.sin(b)),.018,"rust",name="razor_coil")
            m.box((x,.73,0),(.09,.04,.06),"steel",name="razor_barbs")
        if "coiled" in v: tip(m,(0,math.pi/2,0))
        if "damaged" in v: m.beam((.5,.7,0),(1.6,.1,0),.022,"rust",name="loose_wire")
    elif n==122:
        m.profile([[-.35,0],[.35,0],[.4,1.2],[.28,1.45],[-.28,1.45],[-.4,1.2]],.075,mat="paint",solid=True,name="ballistic_shield")
        m.box((0,1.1,-.045),(.36,.15,.03),"glass",name="view_port")
        m.handle((0,.8,.08),.24)
        m.box((0,.04,.25),(.6,.08,.55),"steel",True,name="shield_kickstand")
        if "leaning" in v: tip(m,(.2,0,0))
        if "damaged" in v:
            for x in [-.12,.08]: m.cyl((x,.55,-.052),.025,.015,"steel",2,name="impact_dents")
    elif n==123:
        m.cabinet(.75,1.9,.6,open="open" in v or "forced" in v,shelves=3)
        m.box((0,1.6,-.34),(.3,.12,.02),"warning",name="locker_stencil")
        if "forced" in v: m.box((.32,1,-.39),(.07,.2,.03),"rust",name="torn_lock_lug")
    elif n==124:
        m.table(1.7,.85,.8,"steel")
        for x in [-.5,0,.5]: m.screen((x,1.18,0),.46,.35,"active" in v)
        m.box((0,.87,-.25),(1.1,.05,.22),"rubber",name="surveillance_keyboard")
        if "destroyed" in v: m.box((.35,.85,.1),(.3,.08,.2),"rust",name="monitor_fragments")
    elif n==125:
        m.box((0,.1,0),(.3,.2,.3),"steel",True,name="beacon_mount")
        m.cyl((0,.32,0),.12,.28,"red",name="beacon_lens")
        m.cyl((0,.49,0),.14,.06,"steel",name="beacon_cap")
        if "flashing" in v: m.cyl((0,.32,-.02),.06,.15,"light",name="beacon_bulb")
        if "damaged" in v: m.box((.08,.3,-.1),(.1,.12,.02),"rubber",name="lens_fracture")


def camp(m: Model):
    n,v=m.id,m.variant
    if n==126: bed(m,n)
    elif n in [127,128]:
        w,d,h=(1.6,2.2,1.4) if "small" in v else (2.6,3.0,1.8)
        if n==128: w,d,h=2.4,2.0,1.7
        if "collapsed" in v: h=.35
        for x in [-w/2,w/2]:
            for z in [-d/2,d/2]:
                m.beam((x,.03,z),(0,h,z*.9),.045,"wood",True,"tent_poles")
                m.beam((x,.04,z),(x*1.25,.025,z*1.2),.018,"cloth_dark",name="guy_rope")
        m.beam((0,h,-d/2),(0,h,d/2),.05,"wood",True,"ridgepole")
        for side in [-1,1]:
            m.profile([[0,h],[side*w/2,.08],[side*w/2,.14],[0,h+.06]],d,(0,0,0),"cloth_dark",False,name="tarp_roof")
        if n==127:
            m.profile([[-w/2,.08],[w/2,.08],[0,h]],.035,(0,0,d/2),"cloth",False,name="tent_back")
            # Split entrance panels leave a real opening at the front.
            for x in [-w*.36,w*.36]: m.box((x,h*.25,-d/2),(.3,h*.5,.035),"cloth",name="entrance_flaps")
        if "patched" in v: m.box((w*.3,h*.4,-.2),(.35,.35,.04),"cloth",rot=(0,0,.5),name="sewn_patch")
        if "torn" in v: m.box((-w*.3,h*.3,-d/2),(.22,.5,.04),"cloth",name="hanging_tarp_strip")
    elif n==129:
        h=1.7 if "tall" in v else .9
        for x in [-1,1]: m.box((x,h/2,0),(.1,h,.18),"wood",True,name="scrap_posts")
        for j in range(5): m.box((-.85+j*.42,h/2,-.025*(j%2)),(.38,h*.85,.06),"rust" if j%2 else "paint",True,rot=(0,0,.04*(j-2)),name="overlapping_scrap_panels")
        m.beam((-1,.1,.2),(1,h-.1,.2),.08,"wood",True,"rear_brace")
        if "corner" in v: m.box((1,h/2,.5),(.08,h,1.2),"rust",True,name="return_panel")
        if "damaged" in v: m.parts=[p for p in m.parts if not(p["component"]=="overlapping_scrap_panels" and p["at"][0]>.7)]
    elif n in [130,139]:
        electric="electric" in v
        if electric:
            m.box((0,.3,0),(.6,.6,.35),"steel",True,name="heater_case")
            for j in range(6): m.box((-.22+j*.09,.3,-.19),(.025,.4,.03),"red",name="heater_elements")
            m.box((0,.3,-.22),(.55,.04,.035),"steel",name="element_guard")
        else:
            m.cyl((0,.32,0),.3,.64,"rust",solid=True,name="stove_barrel")
            m.box((0,.22,-.3),(.3,.25,.035),"rubber",name="firebox_opening")
            m.box((0,.66,0),(.7,.06,.6),"steel",True,name="cooking_plate")
            m.pipe((.2,.6,.2),(.2,1.8,.2),.06,"rust",False)
            m.cyl((0,.74,-.02),.17,.14,"steel",name="cooking_pot")
            if "gas" in v: m.cyl((.5,.25,0),.16,.5,"paint",solid=True,name="gas_bottle")
        if "broken" in v: m.box((.15,.06,-.4),(.3,.05,.18),"rust",name="fallen_stove_door")
    elif n==131:
        for j in range(10):
            a=j*math.tau/10; m.box((.5*math.cos(a),.1,.5*math.sin(a)),(.25,.2,.22),"concrete",True,rot=(0,a,0),name="fire_ring_stones")
        for j in range(3): m.box((0,.09+j*.07,0),(.55,.08,.1),"wood" if "cold" in v else "rubber",rot=(0,j*1.1,0),name="firewood")
        if "burning" in v:
            for j in range(3): m.profile([[-.09,0],[.09,0],[.03,.3]],.08,(-.16+j*.16,.2,0),"warning",name="embers")
        if "extinguished" in v: m.box((0,.025,0),(.65,.05,.65),"dirt",name="ash_bed")
    elif n==132: interior(m)
    elif n==133:
        m.cyl((0,.45,0),.4,.9,"plastic",solid=True,name="collection_barrel")
        for x in [-.7,.7]: m.box((x,.85,0),(.06,1.7,.06),"wood",True,name="collector_posts")
        m.profile([[-.8,1.7],[0,1.1],[.8,1.7],[.8,1.76],[0,1.17],[-.8,1.76]],1.4,mat="cloth",name="funnel_tarp")
        if "full" in v: m.cyl((0,.88,0),.35,.025,"glass",name="collected_water")
        if "damaged" in v: m.box((.3,.03,0),(.8,.025,.5),"glass",name="leaking_water")
    elif n==134:
        for x in [-1,1]: m.box((x,.9,0),(.08,1.8,.08),"wood",True,name="drying_posts")
        for y in [1.3,1.7]: m.box((0,y,0),(2.1,.025,.025),"cloth_dark",name="clothesline")
        if "empty" not in v:
            for x in [-.6,0,.6]: m.box((x,1.4,0),(.3,.5,.06),"cloth" if "clothes" in v else "wood",name="drying_supplies")
    elif n==135:
        if "rolled" in v:
            m.cyl((0,.2,0),.2,.65,"cloth_dark",0,False,name="rolled_blanket")
            for x in [-.2,.2]: m.cyl((x,.2,0),.215,.055,"cloth",0,name="bedroll_straps")
        else:
            m.box((0,.055,0),(.7,.11,1.9),"cloth_dark",name="sleeping_mat")
            m.box((0,.13,.15),(.65,.1,1.4),"cloth",name="blanket")
            m.box((0,.16,-.7),(.5,.16,.3),"cloth",name="pillow")
            if "abandoned" in v: m.box((.2,.22,.6),(.3,.08,.3),"cloth_dark",name="rumpled_blanket")
    elif n==136:
        raised="raised" in v; h=2.2 if raised else .8
        m.feet(1.8,1.6,h,"wood",.15)
        m.box((0,h,0),(2,.15,1.8),"wood",True,name="watch_platform")
        for x in [-.9,.9]:
            m.box((x,h+.8,0),(.12,1.6,.12),"wood",True,name="watch_posts")
            m.box((x,h+.7,0),(.08,.12,1.8),"wood",True,name="watch_railings")
        m.box((0,h+1.6,0),(2.2,.08,2),"cloth_dark",name="watch_roof")
        if raised:
            for j in range(7): m.box((0,.2+j*.3,1),(.6,.06,.06),"wood",True,name="access_ladder")
            for x in [-.32,.32]: m.box((x,1.1,1),(.06,2.2,.06),"wood",True,name="ladder_stiles")
        if "reinforced" in v: m.box((0,h+.5,-.88),(1.8,.8,.06),"rust",True,name="defensive_plate")
    elif n==137:
        debris(m,"steel" if "electronics" in v else "rust",True)
        if "electronics" in v:
            m.screen((.3,.4,-.25),.4,.3)
            m.box((-.3,.3,0),(.35,.5,.4),"rubber",name="salvaged_tower")
    elif n==138:
        for x in [-.65,.65]: m.box((x,1,0),(.08,2,.1),"wood",True,name="board_posts")
        m.box((0,1.4,0),(1.5,1,.08),"wood",True,name="notice_board")
        if "blank" not in v:
            for j in range(5):
                m.box((-.5+(j%3)*.45,1.2+(j//3)*.4,-.05),(.3,.3,.025),"medical",rot=(0,0,.04*j),name="paper_notices")
        if "vandal" in v: m.beam((-.6,1.1,-.075),(.6,1.7,-.075),.08,"red",name="painted_warning")
    elif n==139: camp_heater(m)
    elif n==140:
        m.chest(.8,.4,.5,"wood",open="wall" in v)
        m.box((0,.5,0),(.95,.16,.65),"dirt" if "buried" in v else "cloth_dark",True,name="stash_disguise")
        if "wall" in v: m.frame(.95,.65,.12,"wood")


def camp_heater(m):
    # Shared stove construction; separate entry avoids an unrelated silhouette.
    saved=m.id; m.id=130; camp(m); m.id=saved


def nature(m: Model):
    n,v=m.id,m.variant
    if n in [141,142,149,150]:
        if n in [149,150]:
            length=2.7 if n==149 else .65
            r=.3 if n==149 else .45
            m.cyl((0,r,0) if n==149 else (0,length/2,0),r,length,"wood",2 if n==149 else 1,True,8,"trunk")
            m.cyl((0,r,-length/2-.01) if n==149 else (0,length+.012,0),r*.85,.025,"wood_light",2 if n==149 else 1,name="growth_rings")
            if "decay" in v or "rotten" in v: m.box((r*.6,.2,0),(.18,.3,.5),"dirt",name="rotted_bark")
            if "cut" in v: m.box((.12,.25,-1.4),(.6,.1,.3),"wood_light",name="wood_chips")
            if "overgrown" in v: foliage(m,(0,length+.1,0),.65,5)
        else:
            h=2.5 if "small" in v or "young" in v else 5.5 if "large" in v or "mature" in v else 4.0
            m.profile([[-.25,0],[.24,0],[.17,h*.6],[.06,h],[-.04,h],[-.12,h*.5]],.28,mat="wood",solid=True,name="tapered_trunk")
            for j in range(6):
                side=-1 if j%2 else 1; y=h*(.3+j*.095)
                m.beam((0,y,0),(side*(.6+j*.08),y+.65,(j%3-1)*.45),.11,"wood",True,"branches")
            for j in range(4):
                a=j*math.pi/2; m.beam((0,.25,0),(.55*math.cos(a),.03,.55*math.sin(a)),.12,"wood",True,"root_flare")
            if n==142:
                for y,r in [(h*.55,1.1),(h*.75,.95),(h*.95,.7)]: foliage(m,(0,y,0),r,5)
            if "fallen" in v: tip(m,(0,0,math.pi/2))
            if "damaged" in v: m.box((.15,h*.45,-.15),(.12,.55,.04),"wood_light",name="stripped_bark")
    elif n in [143,144,145,146,153]:
        if n==146:
            for j in range(5):
                a=j*.9; m.beam((0,.1,0),(math.cos(a)*1.1,.05,math.sin(a)*1.1),.1 if "massive" not in v else .22,"wood",True,"root_tendrils")
            if "wall" in v: tip(m,(math.pi/2,0,0))
        elif n==145:
            for j in range(4 if "thin" in v else 7):
                x=-.5+j*.17; m.beam((x,0,0),(x+.2,2,0),.02,"wood",name="vine_stems")
                for y in [.25,.6,1,1.4,1.8]: m.box((x+.1*y,y,-.035),(.14,.12,.035),"dirt" if "dried" in v else "foliage",rot=(0,0,.3*j),name="vine_leaves")
        elif n==144:
            for j in range(18):
                x=((j*7)%13)/13-.5; z=((j*11)%17)/17-.5; h=.25+(j%4)*.07
                if "trampled" in v: h*=.3
                m.profile([[-.04,0],[.04,0],[.02,h]],.025,(x,0,z),"dirt" if "dry" in v else "foliage",name="grass_blades")
        else:
            for j in range(6 if "dense" in v else 3):
                x=(j%3-1)*.35; z=(j//3-.5)*.35
                m.beam((x,0,z),(x+.06,.65,z),.035,"wood",name="bush_stems")
                if "dead" not in v: foliage(m,(x,.5,z),.35,3,"contamination" if n==153 or "infected" in v else "foliage")
            if "discolored" in v or "infected" in v: m.box((0,.6,-.1),(.25,.16,.18),"dirt",name="fungal_growth")
    elif n==147:
        for j in range(7 if "large" in v else 4):
            x=(j%3-1)*.18; z=(j//3)*.2; h=.15+(j%3)*.08
            m.cyl((x,h/2,z),.035,h,"medical",name="mushroom_stem")
            m.profile([[-.14,0],[.14,0],[.1,.07],[0,.12],[-.1,.07]],.2,(x,h,z),"dirt" if "decaying" in v else "medical" if "pale" in v else "wood",name="mushroom_cap")
    elif n in [148,151,155]:
        size=.8 if "small" in v else 2.0 if "large" in v else 1.3
        if n==148:
            for j in range(3):
                m.profile([[-size*.4,0],[size*.4,0],[size*.46,.2],[size*.2,size*.6],[-size*.2,size*.7],[-size*.5,.3]],size*.7,(j*.25,0,j*.15),"concrete",True,name="fractured_rock")
            if "fractured" in v: m.box((size*.5,.15,-.4),(.3,.3,.4),"concrete",True,name="split_rock_fragment")
        elif n==151:
            for j in range(3): m.box((0,.07+j*.1,0),(size-j*.2,.14,size*.8-j*.18),"dirt",False,name="mud_strata")
            if "waterlogged" in v: m.box((.3,.012,0),(size,.025,size*.65),"glass",name="standing_water")
        else:
            m.profile([[-size/2,0],[size/2,0],[size/2,.12],[.2,.15],[-size/2,.1]],size*.7,mat="concrete",solid=True,name="pavement_slab")
            if "raised" in v: tip(m,(.15,0,0))
            if "root" in v: m.beam((-.5,.08,0),(.4,.2,0),.12,"wood",True,"lifting_root")
    elif n==152:
        m.profile([[-.8,0],[-.2,-.3],[.5,-.22],[.85,.1],[.5,.45],[-.55,.4]],.012,(0,.015,0),"water" if "clear" in v else "oil" if "oily" in v else "mud_water",False,2,"puddle")
        tip(m,(math.pi/2,0,0))
        if "stagnant" in v: m.box((.2,.03,0),(.3,.015,.2),"contamination",name="surface_scum")
    elif n==154: debris(m,"wood",False)


def foliage(m,at,r,count=5,mat="foliage"):
    # Deliberate tiered leaf masses, with bark-connected branch origins.
    for j in range(count):
        angle=j*math.tau/count
        x=at[0]+math.cos(angle)*r*.35; z=at[2]+math.sin(angle)*r*.35
        m.profile([[-r*.55,0],[r*.55,0],[r*.65,r*.18],[r*.35,r*.55],[-r*.3,r*.6],[-r*.65,r*.2]],r*.8,(x,at[1]-r*.3,z),mat,name="leaf_mass")


def vehicle(m: Model):
    n,v=m.id,m.variant
    if n in [165,166]:
        bicycle=n==166; r=.34 if bicycle else .3
        for z in [-.7,.7]:
            m.wheel((0,r,z),r,0)
            m.cyl((0,r,z),r*.86,.18,"steel" if bicycle else "rubber",0,name="wheel_spokes")
            m.cyl((0,r,z),r*.73,.19,"rubber",0,name="wheel_void")
        for a,b in [((0,r,-.7),(0,.9,-.3)),((0,.9,-.3),(0,r,.25)),((0,r,.25),(0,r,.7)),((0,r,.7),(0,.88,.35)),((0,.88,.35),(0,.9,-.3))]: m.beam(a,b,.035 if bicycle else .08,"steel",True,"cycle_frame")
        m.box((0,.94,.3),(.24,.08,.3),"rubber",True,name="saddle")
        m.box((0,1.05,-.4),(.65,.04,.05),"steel",name="handlebars")
        m.beam((0,.35,-.7),(0,1.05,-.4),.05,"steel",True,"front_fork")
        if not bicycle:
            m.box((0,.52,0),(.35,.35,.45),"steel",True,name="motorcycle_engine")
            if "stripped" not in v: m.box((0,.85,-.06),(.35,.25,.45),m.paint,True,name="fuel_tank")
            m.cyl((0,.8,-.65),.11,.1,"light",2,name="headlamp")
        if "cargo" in v: m.box((0,.8,.7),(.6,.35,.5),"wood",True,name="cycle_cargo_box")
        if "fallen" in v: tip(m,(0,0,math.pi/2))
        if m.damaged: m.beam((0,1,-.4),(.25,.85,-.5),.04,"rust",name="bent_handlebar")
        return
    if n==167:
        for x in [-.65,.65]:
            for z in [-.65,.65]: m.wheel((x,.28,z),.28)
        m.box((0,.5,0),(1.25,.55,1.7),"warning",True,name="forklift_chassis")
        m.box((0,.9,.35),(.55,.25,.6),"rubber",True,name="driver_seat")
        for x in [-.55,.55]:
            m.box((x,1.4,.4),(.06,1.5,.06),"steel",True,name="overhead_guard_posts")
            m.box((x,1.2,-.85),(.1,2.4,.12),"steel",True,name="mast_rails")
            m.box((x,.13,-1.45),(.12,.1,1.3),"steel",True,name="fork_tines")
        m.box((0,2.18,.3),(1.2,.08,1.1),"steel",True,name="overhead_guard")
        m.box((0,.45,-.85),(1.15,.45,.08),"steel",True,name="carriage")
        if "loaded" in v:
            m.offset=(0,.2,-1.5); pallet(m,True); m.offset=(0,0,0)
        if "wrecked" in v: m.box((.35,.6,-1),(.18,.9,.12),"rust",True,rot=(0,0,.3),name="buckled_mast")
        return
    trailer=n in [168,170]; truck=n in [160,163,164,168]; stripped=n==169 or "stripped" in v
    w=2.35 if truck else 1.75 if trailer else 1.85
    length=10 if n==164 else 7 if truck else 3 if trailer else 4 if n==157 else 5.1 if n in [158,159,161] else 4.5
    axles=[-length*.32,length*.32] if not trailer else [length*.2]
    for x in [-w*.48,w*.48]:
        for z in axles: m.wheel((x,.4 if truck else .33,z),.4 if truck else .33)
    m.box((0,.45,0),(w*.75,.18,length),"steel",True,name="chassis")
    for x in [-w*.3,w*.3]: m.box((x,.35,0),(.1,.16,length),"rust",True,name="chassis_rails")
    paint="rubber" if "burned" in v else "medical" if n==161 else "paint"
    if stripped:
        for j in range(5): m.box((0,.55,-length*.4+j*length*.2),(w*.7,.08,.08),"rust",True,name="chassis_crossmembers")
        if "heavily" not in v: m.box((0,.72,-length*.25),(.65,.4,.7),"steel",True,name="exposed_engine")
        if "truck" in v: m.box((0,.7,length*.2),(w,.12,length*.4),"wood",True,name="remaining_truck_bed")
        return
    if n==168:
        m.cyl((0,1.4,0),.95,length-.5,"medical",2,True,12,"tanker_shell")
        for z in [-2,0,2]: m.cyl((0,1.4,z),.98,.1,"steel",2,name="tanker_bands")
        for z in [-1.5,1.5]: m.cyl((0,2.4,z),.22,.12,"steel",name="tanker_hatches")
        m.box((0,.65,-length/2-.5),(.2,.2,1.0),"steel",True,name="trailer_hitch")
        if "leak" in v: m.box((.8,.025,0),(1.2,.05,2),"oil",name="fuel_spill")
        if "overturned" in v: tip(m,(0,0,math.pi/2))
        return
    if n==170:
        m.box((0,.68,0),(w,.14,length),"wood",True,name="trailer_deck")
        for x in [-w/2,w/2]: m.box((x,.95,0),(.08,.55,length),m.paint,True,name="trailer_sides")
        m.beam((-.7,.5,-1.5),(0,.5,-2.5),.1,"steel",True,"tow_frame")
        m.beam((.7,.5,-1.5),(0,.5,-2.5),.1,"steel",True,"tow_frame")
        if "loaded" in v: m.box((0,1.05,0),(1.2,.6,1.8),"wood",True,name="trailer_cargo")
        if "damaged" in v: m.box((-.8,1,-.8),(.1,.4,.7),"rust",True,rot=(0,0,.3),name="bent_sidewall")
        return
    # A continuous concave body profile leaves visible wheel arches.
    a=length*.32; r=.4 if truck else .33; bottom=.42; top=.95 if not truck else 1.1
    points=[[-length/2,bottom],[-a-r*.95,bottom],[-a-r*.9,.7],[-a-r*.55,.9],[-a+r*.55,.9],[-a+r*.9,.7],[-a+r*.95,bottom],[a-r*.95,bottom],[a-r*.9,.7],[a-r*.55,.9],[a+r*.55,.9],[a+r*.9,.7],[a+r*.95,bottom],[length/2,bottom],[length/2,top],[-length/2,top]]
    m.profile(points,w,mat=paint,solid=False,axis=0,name="wheel_arch_body")
    m.box((0,.7,0),(w-.15,.4,length*.48),paint,True,name="body_collision_core")
    cab_z=-length*.28 if n in [158,160,163] else 0
    cab_d=1.7 if n in [158,160,163] else length*.62
    cab_h=2.5 if truck else 2.0 if n in [159,161] else 1.55
    m.profile([[-cab_d/2,.96],[cab_d/2,.96],[cab_d*.38,cab_h],[-cab_d*.28,cab_h]],w*.9,(0,0,cab_z),"glass" if "burned" not in v else "rubber",True,0,"glazed_cab")
    m.box((0,cab_h+.035,cab_z),(w*.92,.09,cab_d*.7),paint,True,name="roof")
    for x in [-w*.46,w*.46]:
        for z in [-cab_d*.3,0,cab_d*.34]: m.box((x,(cab_h+.96)/2,z+cab_z),(.08,cab_h-.9,.1),paint,True,name="cab_pillars")
        m.box((x,.98,cab_z),(.08,.1,cab_d),"steel",name="window_sill")
        for z in [-cab_d*.23,cab_d*.25]: m.box((x*1.04,.93,cab_z+z),(.04,.04,.2),"steel",name="door_handles")
        m.box((x*1.1,1.15,cab_z-cab_d*.4),(.17,.13,.2),paint,name="wing_mirrors")
    for z in [-length/2,length/2]:
        m.box((0,.55,z),(w,.16,.14),"steel",True,name="bumpers")
        for x in [-w*.36,w*.36]: m.box((x,.85,z*1.012),(.27,.16,.04),"light" if z<0 else "red",name="lamps")
    m.box((0,.77,-length/2-.03),(w*.5,.18,.03),"rubber",name="radiator_grille")
    for j in range(5): m.box((-.35+j*.18,.77,-length/2-.05),(.035,.15,.025),"steel",name="grille_slats")
    if n in [158,160,163]:
        m.box((0,.93,length*.2),(w,.12,length*.45),"wood",True,name="cargo_bed")
        for x in [-w*.48,w*.48]: m.box((x,1.15,length*.2),(.08,.45,length*.45),paint,True,name="bed_sides")
        if n==160:
            for x in [-w*.48,w*.48]: m.box((x,2,length*.19),(.08,2.1,length*.5),"medical",True,name="cargo_box_walls")
            m.box((0,3.03,length*.19),(w,.08,length*.5),"medical",True,name="cargo_box_roof")
            if "open" not in v: m.box((0,1.98,length*.45),(w,2.0,.08),"medical",True,name="cargo_rear_door")
        if n==163 and "covered" in v: m.box((0,1.9,length*.2),(w,.1,length*.45),"cloth_dark",True,name="canvas_cover")
        if "loaded" in v: m.box((0,1.3,length*.2),(1.2,.6,1.3),"wood",True,name="bed_cargo")
    if n==161:
        for side in [-1,1]:
            m.box((side*(w/2+.02),1.1,.6),(.025,.4,.12),"red",name="medical_cross")
            m.box((side*(w/2+.02),1.1,.6),(.025,.12,.4),"red",name="medical_cross")
        m.box((0,cab_h+.12,-.6),(1,.12,.22),"red",name="ambulance_beacon")
    if n==162:
        m.box((0,cab_h+.13,0),(1,.12,.22),"steel",name="lightbar_base")
        for x,mat in [(-.3,"red"),(.3,"light")]: m.box((x,cab_h+.22,0),(.35,.12,.2),mat,name="police_lights")
    if n==164:
        for side in [-1,1]:
            for j in range(8): m.box((side*(w*.46+.01),1.9,-3.5+j),(.025,.65,.8),"glass",name="bus_windows")
        m.box((0,.64,4.4),(w,.12,.8),"steel",True,name="bus_step")
    if n==159 and "open" in v:
        m.box((w*.48,1.3,length*.4),(.08,1.2,.9),paint,True,rot=(0,.6,0),name="open_rear_door")
    if "fortified" in v:
        for y in [1.1,1.35]: m.box((0,y,-length*.25),(w,.06,.06),"steel",True,name="windscreen_bars")
    if any(s in v for s in ["wrecked","crashed","destroyed","ransacked"]):
        m.box((-.25,1.0,-length*.38),(.8,.08,.6),"rust",True,rot=(.18,0,.15),name="crumpled_hood")
        m.parts=[p for p in m.parts if not(p["component"]=="lamps" and p["at"][0]>0)]
    if "abandoned" in v or "rusty" in v: m.box((-.4,.98,length*.3),(.4,.025,.6),"rust",name="body_corrosion")
    if "burned" in v: m.box((0,.98,-length*.34),(w*.7,.025,.5),"dirt",name="fire_exposed_engine")


def storage(m: Model):
    n,v=m.id,m.variant
    opened=any(s in v for s in ["open", "breached", "looted", "forced", "ransacked"])
    if n in [171,172,173,174,175,177,178,188,191,192,198,199]:
        dimensions={171:(.85,.55,.65),172:(.95,.7,.75),173:(.5,.3,.3),174:(1.05,.5,.6),
                    175:(.6,.25,.4),177:(.65,.38,.45),178:(.55,.28,.3),188:(.65,.24,.45),
                    191:(.55,.4,.4),192:(.65,.45,.45),198:(1.2,.18,.4),199:(.75,.3,.5)}
        w,h,d=dimensions[n]
        if "small" in v: w*=.75;h*=.8;d*=.8
        if "large" in v or "medium" in v: w*=1.25;h*=1.2
        mat="wood" if n==171 else "cardboard" if n==191 and "cardboard" in v else "plastic" if "plastic" in v else "medical" if n in [175,177,192,199] else m.paint
        m.chest(w,h,d,mat,opened,ribs=n in [171,172,174,198,199])
        if n==171:
            for y in [h*.2,h*.45,h*.7]: m.box((0,y,-d/2-.015),(w,.018,.02),"wood_light",name="plank_joints")
            if "reinforced" in v:
                m.beam((-w*.4,.05,-d/2-.07),(w*.4,h-.05,-d/2-.07),.09,"wood",name="diagonal_batten")
        if n in [175,199]:
            m.group="panel"
            m.box((0,h+.058,0),(.22,.025,.07),"red" if n==175 else "paint",name="medical_emblem")
            m.box((0,h+.058,0),(.07,.025,.22),"red" if n==175 else "paint",name="medical_emblem")
            m.group="body"
        if n==173:
            for x in [-w*.3,w*.3]: m.box((x,h*.5,-d/2-.025),(.06,h*.7,.03),"steel",name="pressed_ribs")
        if n in [177,192] and ("refrigerated" in v or n==192):
            m.box((w/2+.04,h*.5,0),(.08,h*.7,d*.7),"steel",True,name="cooler_compressor")
            for y in [h*.25,h*.4,h*.55,h*.7]: m.box((w/2+.09,y,0),(.03,.02,d*.55),"rubber",name="cooler_vents")
        if n==178:
            m.group="panel"; m.box((0,h+.08,0),(.2,.03,.12),"rubber",name="toolbox_handle_grip"); m.group="body"
            if "industrial" in v: m.box((0,.025,0),(w+.08,.05,d+.08),"steel",True,name="toolbox_impact_base")
        if n==188:
            for x in [-w*.3,w*.3]: m.box((x,h*.3,-d/2-.02),(.08,.08,.035),"rubber",name="shock_protectors")
        if n==191:
            m.group="panel"; m.box((0,h+.058,0),(.07,.025,d),"medical",name="sealing_tape"); m.group="body"
            if "rotten" in v: m.box((w*.2,.1,-d*.3),(.22,.1,.18),"contamination",name="mold_at_seam")
        if n in [198,199]:
            m.group="body"
            m.box((0,h*.5,-d/2-.04),(.18,.09,.04),"rubber",name="combination_lock")
            if "reinforced" in v or "secure" in v or "locked" in v:
                for x in [-w*.42,w*.42]: m.box((x,h*.5,0),(.04,h+.06,d+.07),"steel",name="security_straps")
        m.group="contents"
        if not any(s in v for s in ["looted","broken","stripped"]):
            if n==198:
                m.box((0,h*.6,0),(w*.72,.065,.12),"steel",name="stored_weapon")
                m.box((w*.25,h*.6,.04),(.16,.08,.16),"wood",name="stored_weapon_stock")
            elif n in [175,177,199]:
                for x in [-w*.22,w*.22]: m.cyl((x,h*.6,0),min(.04,h*.18),h*.5,"medical",name="medical_vials")
            else: m.box((0,h*.4,0),(w*.55,h*.45,d*.55),"cardboard",name="packed_supplies")
        m.group="body"
    elif n==176:
        m.cabinet(.5,.65,.18,"medical",opened,2)
        m.group="panel"
        m.box((0,.35,-.13),(.22,.06,.025),"red",name="first_aid_cross")
        m.box((0,.35,-.13),(.06,.22,.025),"red",name="first_aid_cross")
        m.group="body"
    elif n==179:
        w=1.25 if "large" in v else .7
        m.cabinet(w,.9,.5,"paint",m.damaged,5,True)
        for x in [-w*.4,w*.4]:
            for z in [-.18,.18]: m.wheel((x,.09,z),.09)
        m.box((0,.95,0),(w+.04,.05,.55),"rubber",True,name="chest_worktop")
    elif n in [180,181,182]:
        w,h,d=(.7,.35,.35) if n==180 else (.42,.6,.25) if n==181 else (.65,.8,.26)
        mat="plastic" if "hard-shell" in v else "cloth_dark" if "tactical" in v else "cloth"
        m.profile([[-w*.45,0],[w*.45,0],[w*.5,h*.15],[w*.47,h*.8],[w*.3,h],[-w*.3,h],[-w*.5,h*.75]],d,mat=mat,solid=True,name="bag_shell")
        m.panel((0,h*.65,-d/2-.02),(w*.85,h*.55,.035),mat,"drawer",False)
        m.handle((0,h+.05,0),w*.45,"cloth_dark")
        if n==181:
            for x in [-w*.3,w*.3]:
                m.box((x,h*.5,d/2+.045),(.06,h*.75,.04),"cloth_dark",name="shoulder_straps")
                if "tactical" in v or "scavenger" in v: m.box((x,h*.3,-d/2-.08),(.14,.2,.09),"cloth_dark",name="utility_pouches")
            if "hiking" in v:
                m.cyl((0,h+.12,0),.12,w,"cloth_dark",0,name="attached_bedroll")
        if n==180:
            for x in [-w*.25,w*.25]: m.box((x,h*.7,0),(.05,.04,d+.03),"cloth_dark",name="carry_straps")
            if "overstuffed" in v: m.box((0,h+.04,0),(w*.65,.12,d*.8),"cloth",name="bulging_top")
        if n==182:
            for x in [-w*.35,w*.35]: m.wheel((x,.045,.1),.045)
            for x in [-.12,.12]: m.box((x,h+.15,.08),(.025,.3,.025),"steel",name="telescoping_handle")
            m.box((0,h+.3,.08),(.28,.04,.04),"rubber",name="luggage_handle")
        if m.worn: m.box((w*.25,h*.3,-d/2-.05),(.15,.12,.025),"cloth_dark",name="sewn_repair")
        if m.damaged: m.box((-.2,h*.4,-d/2-.05),(.13,.18,.03),"dirt",name="torn_lining")
    elif n==183:
        m.cabinet(.62,1.85,.55,"paint",opened,2)
        m.group="panel"
        for y in [1.4,1.48,1.56]: m.box((0,y,-.32),(.3,.025,.02),"rubber",name="locker_louvers")
        m.group="body"
        if "military" in v: m.box((0,1.7,-.32),(.22,.07,.025),"warning",name="unit_stencil")
        if "industrial" in v: m.box((0,.1,-.32),(.4,.06,.03),"steel",name="kickplate")
    elif n in [184,185]:
        w,h,d=(.55,.45,.24) if n==184 else (.8,1.0,.7)
        if "heavy" in v or "reinforced" in v: w*=1.25;h*=1.1;d*=1.2
        m.cabinet(w,h,d,"steel",opened,1)
        m.group="panel"
        m.cyl((0,h*.5,-d/2-.09),.09,.055,"steel",2,name="safe_combination_dial")
        for a in [0,math.pi/2,math.pi]: m.beam((w*.27,h*.5,-d/2-.1),(w*.27+.09*math.cos(a),h*.5+.09*math.sin(a),-d/2-.1),.025,"steel",name="safe_handle_spokes")
        for x in [-w*.4,w*.4]:
            for y in [.08,h-.08]: m.box((x,y,-d/2-.065),(.05,.05,.025),"steel",name="safe_door_bolts")
        m.group="body"
        if "breached" in v or "damaged" in v: m.box((w*.35,h*.5,-d/2-.07),(.08,.3,.04),"rust",name="cut_lock_seam")
    elif n in [186,187]:
        m.box((0,.08,0),(.55,.16,.42),"steel",True,name="cash_drawer_case")
        m.panel((0,.08,-.22),(.48,.12,.045),"steel","drawer",opened or "smashed" in v)
        m.box((0,.055,-.07),(.45,.025,.3),"rubber",name="cash_tray")
        for x in [-.15,0,.15]: m.box((x,.085,-.06),(.025,.04,.3),"steel",name="coin_dividers")
        if n==186:
            if "old" in v:
                m.box((0,.32,.06),(.5,.35,.3),m.paint,True,name="register_housing")
                for j in range(5): m.cyl((-.16+j*.08,.33,-.12),.025,.03,"medical",2,name="register_keys")
                m.box((0,.54,.06),(.48,.12,.09),"glass",name="mechanical_total")
            else:
                m.screen((0,.5,.05),.48,.32,not m.damaged)
                m.box((0,.3,.1),(.07,.35,.08),"steel",name="register_display_mount")
        if m.damaged: m.box((.2,.2,-.15),(.12,.08,.08),"rust",name="broken_cash_lock")
    elif n==189:
        h=.55 if "workstation" not in v else .72
        m.cabinet(.25,h,.5,"rubber","stripped" in v,0)
        m.box((0,h*.75,-.27),(.2,.035,.025),"steel",name="optical_drive")
        m.cyl((.07,h*.92,-.27),.018,.02,"steel",2,name="power_button")
        m.group="contents"
        if "stripped" not in v:
            m.box((-.08,h*.5,.03),(.025,h*.7,.35),"paint",name="motherboard")
            m.box((0,.1,.08),(.2,.15,.25),"steel",name="power_supply")
            fan(m,(0,h*.55,-.25),.07)
        m.group="body"
    elif n==190:
        m.cabinet(.65,2.0,.9,"steel","damaged" in v,5)
        m.group="panel"; m.box((0,1.05,-.51),(.44,1.6,.025),"glass",name="server_door_window"); m.group="body"
        for y in [.25,.55,.85,1.15,1.45,1.75]:
            m.box((0,y,-.35),(.53,.16,.55),"rubber",True,name="rack_servers")
            for j in range(3): m.box((-.17+j*.07,y,-.64),(.04,.025,.02),"light" if "secured" in v else "paint",name="drive_lights")
    elif n==193:
        m.cabinet(.95,1.9,.45,"wood","ransacked" in v,4)
        m.group="contents"
        for row in range(3):
            for j in range(4 if "full" in v else 1): m.cyl((-.3+j*.2,.32+row*.4,0),.065,.18,"medical",name="food_tins")
        m.group="body"
    elif n in [194,195]:
        w,h,d=(.55,.85,.55) if n==194 else (1.8,1.3,1.1)
        if "commercial" in v: w=.85;h=1.1;d=.7
        if "industrial" in v: w=1.1;h=1.3;d=.9
        m.chest(w,h,d,"plastic" if n==194 else m.paint,opened or "overflowing" in v,False)
        for x in [-w*.4,w*.4]:
            for z in [-d*.38,d*.38]: m.wheel((x,.1,z),.1)
        if n==195:
            for x in [-w*.25,w*.25]: m.box((x,h*.5,-d/2-.05),(.2,.15,.1),"steel",name="fork_pockets")
        if "overflowing" in v:
            m.group="contents"
            for x in [-.5,0,.5]: m.box((x,h+.1,0),(.4,.3,.5),"rubber",name="overflowing_bags")
            m.group="body"
        if "burned" in v: m.box((0,h*.5,-d/2-.02),(w*.7,.45,.03),"rubber",name="soot_on_body")
    elif n==196:
        m.chest(.6,.35,.45,"plastic" if "plastic" in v else "steel" if "metal" in v else "wood",False)
        m.box((0,.06,0),(1,.12,.8),"dirt",False,name="dug_earth_rim")
        m.group="panel"; m.box((0,.42,0),(.65,.05,.5),"dirt",name="soil_camouflage"); m.group="body"
        m.box((.32,.1,.28),(.12,.09,.1),"concrete",name="cache_marker_stone")
    elif n==197:
        m.frame(.75,.75,.18,"wood")
        m.box((0,.38,.13),(.7,.7,.06),"wood",True,name="compartment_back")
        m.panel((0,.38,-.02),(.65,.65,.05),"wood" if "concealed" in v else "steel","hinge",opened or "exposed" in v)
        if "concealed" in v:
            m.group="panel"; m.box((0,.4,-.055),(.5,.4,.02),"cloth",name="concealing_wall_picture"); m.group="body"
    elif n==200:
        w,h,d=1.6,1.65,1.2
        m.cabinet(w,h,d,"medical" if "medtac" in v else "paint",opened,2)
        for x in [-w*.45,w*.45]:
            m.box((x,h/2,0),(.12,h+.06,d+.06),"steel",True,name="security_corner_frames")
            m.group="panel"; m.box((x*.65,h/2,-d/2-.06),(.035,h*.85,.05),"steel",True,name="locking_rods"); m.group="body"
        m.group="panel"
        m.box((w*.28,h*.55,-d/2-.09),(.22,.28,.08),"rubber",name="electronic_lock")
        for i in range(3): m.box((w*.28,h*.5+i*.05,-d/2-.14),(.12,.02,.015),"light",name="lock_keypad")
        m.group="body"


def metadata(entry, models):
    n=entry["number"]
    interior_ids=set(range(41,67))|set(range(96,111))|{74,82,83,89,94,95,114,115,116,123,124,176,177,179,183,184,185,186,187,189,190,193,197}
    exterior_ids=set(range(1,21))|{27,28,29,30,31,32,36,37,38,40,70,71,76,77,81,87,111,112,113,119,120,121}|set(range(126,156))|set(range(156,171))
    room={1:["street","checkpoint"],2:["entrance","utility"],3:["office","residence"],4:["workshop","factory"],5:["utility","plant"],6:["ward","treatment","laboratory"],7:["checkpoint","security"],8:["camp"],9:["garden","wilderness"],10:["street","parking","loading"],11:["storage","warehouse"]}[entry["category_index"]]
    room=list(room)
    if n in [43,44,58,114,186,187,189]: room=["office","records","reception"]
    if n in [49,50,51,126,135]: room=["residence","dormitory","camp"]
    if n in [52,53,54,55,56,191,192,193]: room=["kitchen","staff_room"] if n not in [55,56] else ["bathroom","washroom"]
    if n in [96,97,98,99,100,101]: room=["ward","treatment","triage"]
    if n in [102,103]: room=["procedure","treatment"]
    if n in [104,105,106,110,177,199]: room=["laboratory","cold_storage","research"]
    if n in [116,117,123,173,174,198,200]: room=["security","armory","checkpoint"]
    if n in [61,62,63,64,65,66,69,132,178,179]: room=["workshop","maintenance"]
    mounts={21:"wall",22:"wall",23:"wall",24:"wall",25:"wall",26:"wall",27:"rooftop",28:"wall",29:"wall",30:"wall",32:"wall",33:"wall",34:"wall",35:"wall",38:"rooftop",39:"wall",59:"wall",76:"ceiling",77:"ceiling",83:"wall",145:"wall",176:"wall",184:"wall",197:"wall"}
    searchable=n>=171 or n in [9,41,43,51,52,53,61,62,82,95,104,113,114,123,132,140]
    profile="technical"
    if n in [43,114,186,187,197]: profile="records"
    if n in [51,113,123,180,181,182,183,194,195]: profile="personal"
    if n in [104,175,176,177,192]: profile="medical"
    if n in [199]: profile="specimen"
    if n in [173,117]: profile="ammo"
    if n in [174,198,200]: profile="weapons"
    if n in [53,191,193]: profile="food"
    if n in [184,185]: profile="records"
    restrictions={"medical":["medical","item"],"specimen":["item","medical"],"ammo":["ammo","magazine"],"food":["food"],"weapons":["weapon","attachment","magazine","ammo"]}.get(profile,[])
    dims=[8,6] if n in [51,53,95,104,183,190,193,195,200] else [10,5] if n==198 else [6,4] if n>=171 else [8,5]
    if n in [175,176,178,184,186,187,188,189,196,197]: dims=[5,4]
    classifications=["decorative"]
    if n in [1,15,66,70,71,80,81,111,112,122,129,148,156,157,158,159,160,161,162,163,164,168,185,200]: classifications.append("hard_cover" if n not in [111,129] else "soft_cover")
    if n in [41,45,48,61,79,96,113,123]: classifications.append("partial_cover")
    if n in [30,31,136,155]: classifications.append("traversable")
    if n in [71,90,91,92,108,121,131,139,153]: classifications.append("hazard")
    if searchable: classifications += ["searchable","interactive"]
    if any(p["collision"] for model in models for p in model.parts): classifications.append("obstacle")
    faction="medtac" if n in range(96,111) or n==199 else "military" if n in range(111,126) or n in [173,174,198] else "scavenger" if n in range(126,141) or n in [196,197] else "civilian"
    building=["hospital","research"] if faction=="medtac" else ["security"] if faction=="military" else ["camp"] if faction=="scavenger" else ["industrial"] if 61<=n<=95 else ["residential","office"] if 41<=n<=60 else ["urban","industrial"]
    return dict(classifications=classifications,placement=dict(
        environments=["interior"] if n in interior_ids else ["exterior"] if n in exterior_ids else ["interior","exterior"],
        rooms=room, buildings=building,factions=[faction,"neutral"],attachment=mounts.get(n,"floor"),
        rotations=[0,90,180,270],rarity=.25 if n in [64,66,80,110,163,168,185,199,200] else .75,
        cluster=[2,6] if n in [2,11,13,14,90,91,143,144,147,154,171,172,191] else [1,1],
        conditions=["abandoned","weathered","dry","wet"] if n not in [89,95,104,110,177,190,199] else ["sheltered","dry"],
        service_clearance=1.0 if 61<=n<=95 else .85 if searchable else .15,
        keep_out_of=["doorway","navigation_route","extraction","spawn"],
        support_elevation=1.1 if mounts.get(n)=="wall" else 2.6 if mounts.get(n)=="ceiling" else 0),
        storage=dict(profile=profile,dimensions=dims,allowed_categories=restrictions,search_seconds=4 if n in [185,190,199,200] else 2,
                     key_item="medtac_keycard" if n in [177,184,185,190,199,200] else "") if searchable else {})


AUTHORS=[street,exterior,interior,industrial,utility,medical,security,camp,nature,vehicle,storage]


def read_catalog():
    entries=[]; category=""; category_index=0
    for line in (ROOT/"docs/environment-prop-catalog.md").read_text(encoding="utf-8-sig").splitlines():
        heading=re.match(r"## (\d+) [—–-] (.*?) \(",line)
        if heading: category_index=int(heading[1]); category=heading[2]
        match=re.match(r"(\d{3})\. (.*?) — (.*)",line)
        if match:
            entries.append(dict(id=match[1],number=int(match[1]),name=match[2],category=category,
                                category_index=category_index,variant_names=[x.strip() for x in match[3].split(",")]))
    assert [e["number"] for e in entries]==list(range(1,201)), "Catalog must contain 001–200 exactly once"
    return entries


def build_recipes():
    entries=read_catalog()
    for e in entries:
        models=[]
        for index,name in enumerate(e["variant_names"]):
            m=Model(e["number"],name,index)
            AUTHORS[e["category_index"]-1](m)
            m.authored_condition()
            m.damage_edges()
            assert m.parts,(e["id"],name,"unfinished recipe")
            if e["category_index"] not in [9] and e["number"] not in [14,17,20,86,111,112,137]:
                assert len(set(p["component"] for p in m.parts))>=2,(e["id"],name,"missing construction details")
            models.append(m)
        e.update(metadata(e,models))
        e["variants"]=[]
        for m,name in zip(models,e.pop("variant_names")):
            v=dict(name=name,index=m.index,parts=m.parts,pivot=m.pivot,opening=m.opening,initial_open=m.initial_open,
                   locked=any(s in m.variant for s in ["locked","secure","sealed"]) and bool(e["storage"].get("key_item")),
                   empty=any(s in m.variant for s in ["empty","looted","stripped","ransacked"]))
            e["variants"].append(v)
        assert 1<=len(e["variants"])<=4
    return entries


def self_check(entries):
    material_names={"concrete","steel","paint","rust","rubber","wood","wood_light","medical","glass","red","light","warning","dirt","contamination","cloth","cloth_dark","foliage","plastic","cardboard","water","oil","mud_water"}
    for e in entries:
        for variant in e["variants"]:
            for p in variant["parts"]:
                assert p["material"] in material_names,(e["id"],p["material"])
                assert all(math.isfinite(x) for x in p["at"]+p["rotation"])
                if p["shape"]=="box": assert min(p["size"])>0
                if p["shape"]=="cylinder": assert p["radius"]>0 and p["length"]>0
            if e["storage"]:
                assert any(p["group"]=="panel" for p in variant["parts"]),(e["id"],"missing moving panel")
    assert len([e for e in entries if e["number"]>=171])==30


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true",help="Validate authoring without writing")
    args=parser.parse_args()
    entries=build_recipes(); self_check(entries)
    if not args.check:
        out=ROOT/"resources/environment_props/recipes.json"
        out.parent.mkdir(parents=True,exist_ok=True)
        out.write_text(json.dumps(entries,separators=(",",":"),ensure_ascii=False)+"\n",encoding="utf-8")
    print(f"PROP RECIPES: {len(entries)} IDs, {sum(len(e['variants']) for e in entries)} authored variants")


if __name__=="__main__": main()



