function bots_mean(params)
	local function send(p,f,t)return{percent=p,from=f.ships and{f.n}or f,to=t.n}end
	local function redirect(f,t)return{from=f.ships and{f.n}or f,to=t.n}end
	local function distance(a,b)local dx,dy=b.x-a.x,b.y-a.y return sqrt(dx*dx+dy*dy)end
	local G,USER,memory=params.items,params.user,params.memory
	local FIRST=not memory.init
	if FIRST then memory.init=true end
	local uteam=G[USER].team
	local homes,eteam=memory.homes,memory.eteam
	if not homes then
		homes={}
		for _,v in pairs(G)do
			if v.is_planet and not v.neutral then
				local o=v.team
				local h=homes[o]
				if not h or h.production<v.production then
					homes[o]=v
				end
			end
		end
		for k,v in pairs(homes)do if k~=uteam then memory.eteam,eteam=k,k end end
		memory.homes=homes
	end
	local home,ehome=homes[uteam],homes[eteam]
	local ships,total,tprod,myprod,ecount=0,0,0,0,0
	local enemies,eprod={},{}
	local data={planets={},neutral={},myplanets={},myteam={},eplanets={},others={},fleets={},myfleets={},efleets={},mystuff={}}
	for _,p in pairs(G)do
		local o,s=p.team,p.ships
		if not p.is_user and not p.neutral then
			if o==uteam then
				ships=ships+s
			elseif not enemies[o]then
				enemies[o]=s
				ecount=ecount+1
			else
				enemies[o]=enemies[o]+s
			end
			total=total+s
		end
		if p.is_planet then
			data.planets[#data.planets+1]=p
			if p.neutral then
				data.neutral[#data.neutral+1]=p
				data.others[#data.others+1]=p
			else
				tprod=tprod+p.production
				if o==uteam then
					data.myteam[#data.myteam+1]=p
					if p.owner==USER then
						myprod=myprod+p.production
						data.myplanets[#data.myplanets+1]=p
						data.mystuff[#data.mystuff+1]=p
					end
				else
					local x=eprod[o]
					if not x then
						eprod[o]=p.production
					else
						eprod[o]=x+p.production
					end
					data.others[#data.others+1]=p
					data.eplanets[#data.eplanets+1]=p
				end
			end
		elseif p.is_fleet then
			data.fleets[#data.fleets+1]=p
			if p.team==uteam then
				data.myfleets[#data.myfleets+1]=p
				data.mystuff[#data.mystuff+1]=p
			else
				data.efleets[#data.efleets+1]=p
			end
		end
	end
	if ecount == 1 and ehome and tprod >= myprod*2 then
		local dist, closest = HUGE, home
		for _, a in pairs(data.myplanets) do
			for _, b in pairs(data.eplanets) do
				local d = distance(a, b)
				if dist > d then dist, closest = d, a end
			end
		end
		ships = ships + dist*closest.production/2000
	end
	local planets,control=data.myplanets,ships/total
	local bigv,bigp,big=0
	for e,v in pairs(enemies)do
		local v=v/total enemies[e]=v
		if v>.5 then
			big=e
		elseif v>.4 then
			if big then big=nil else big=e end
		end
	end
	for e,v in pairs(eprod)do
		local n=v/tprod
		if n>bigv then bigv,bigp=n,e end
	end
	local hide=false
	local ships0,ships1,big0,big1=0,0
	for e,v in pairs(enemies)do
		if v>ships0 then
			ships0,ships1=v,ships0
			big0,big1=e,big0
		elseif v>ships1 then
			ships1,big1=v,e
		end
	end
	if big and (big1 and control*2<ships1 and ships0<.6)or(bigp and big~=bigp)then
		hide,big=big
	end
	local control2 = control/(1-ships0)
	if FIRST and home and #data.neutral~=0 and ecount == 1 then
		local function path(f,t,set)
			local ft=distance(f,t)
			for i=1,#set do local p=set[i]
				if p~=f and p~=t then
					local pt=distance(p,t)
					if pt<ft then
						local fp=distance(f,p)
						if fp<ft and(pt+fp-p.r*2)<ft then
							t,ft=p,fp
						end
					end
				end
			end
			return t
		end
		local function recovertime(a,b)
			local r=b.ships-a.ships
			if r<0 then
				return distance(a,b)/20+b.ships*50/b.production
			elseif a.is_planet then
				return distance(a,b)/20+b.ships*50/b.production+r*50/a.production
			else
				return HUGE
			end
		end
		local function pathlength(f,t,set)
			local d=0
			for i=1,20 do
				if f==t then break end
				local F=path(f,t,set)
				d=d+distance(f,F)
				f=F
			end
			return d
		end
		local eeval,enemy=HUGE
		for _,v in pairs(data.eplanets)do
			local n=distance(v,home)
			if eeval>n then eeval,enemy=n,v end
		end
		if not enemy then
			local eeval=-HUGE
			for _,v in pairs(data.others)do
				local n=distance(v,home)
				if n>eeval then eeval,enemy=n,v end
			end
		end
		local p,expand=data.neutral,{}
		local rt={}for _,v in pairs(p)do rt[v]=recovertime(home,v)end
		sort(p,function(a,b)return rt[a]<rt[b]end)
		local c=home.ships
		local cinit,ships,n,excess=c,c,0,0
		local benefit=home.production*distance(enemy,home)/2000
		local prod=home.production
		for i=1,#p do local v=p[i]
			if home and enemy and distance(enemy,v)<distance(home,v)then break end
			local s=max(1,v.ships+1)
			local ben=((distance(enemy,v)-pathlength(home,v,expand))/40)*v.production/50-s
			local liability = s - max(c, 0)
			if c<s then
				ben=ben-(excess+liability)*v.production/prod
			end
			if benefit+ben+c>cinit then
				if c < s then
					excess = excess + liability
				end
				benefit=benefit+ben
				c=c-s
				if c>0 then prod=prod+v.production end
				expand[#expand+1]=v
			end
		end
		memory.expand=expand
		return
	end
	local stuff=data.mystuff
	sort(stuff,function(a,b)return a.ships>b.ships end)
	local targets = {}
	for _, p in pairs(data.eplanets) do
		targets[#targets+1] = p
	end
	local recall = false
	if (not big or (big and ecount>2)) and ((ecount>2 and control2<1/ecount) or (ecount==2 and control<1/6)) then
		-- recall fleets
		for _,v in pairs(stuff)do
			if v.is_fleet and G[v.target].team~=uteam then
				local dist,closest=HUGE
				for _,p in pairs(data.myplanets)do
					local d=distance(p,v)
					if dist>d then dist,closest=d,p end
				end
				if closest then
					return redirect(v,closest)
				end
			end
		end
		recall = true
	end
	local defend=(ecount==1 and myprod/tprod>.5 and control<.8) or recall
	if ecount < 2 then
		targets = data.eplanets
	elseif big then
		targets = {}
		if ecount ~= 2 or not hide then
			local w1, biggest = -1
			for e, v in pairs(enemies) do
				if v > w1 then w1, biggest = v, e end
			end
			for _, p in pairs(data.eplanets) do if p.team == biggest then targets[#targets+1] = p end end
		end
	elseif ecount > 2 then
		targets = {}
		for _, p in pairs(data.eplanets) do
			if enemies[p.team] < ships then
				targets[#targets+1] = p
			end
		end
	elseif ecount == 2 then
		if control > .5 then
			targets = data.eplanets
		else
			targets = {}
			sort(data.neutral, function(a, b) return a.production-a.ships > b.production-b.ships end)
			for i = 1, ceil(#data.neutral/2) do
				targets[#targets+1] = data.neutral[i]
			end
			local w1, biggest = -1
			for e, v in pairs(enemies) do
				if v > w1 then w1, biggest = v, e end
			end
			local p1, largest = -1
			for _, v in pairs(eprod) do
				if v > p1 then p1, largest = v, e end
			end
			if control > w1 and myprod > p1 then
				targets = data.eplanets
			else
				for _, p in pairs(data.eplanets) do if p.team == biggest then targets[#targets+1] = p end end
			end
		end
	end
	if ecount ~= 1 and control < .5 then
		sort(data.myplanets, function(a, b) return a.ships > b.ships end)
		local p = data.myplanets[1]
		if p then
			for _, v in pairs(data.others) do
				local d = distance(p, v)
				if v.ships < ships*.1 and ships - v.ships > d - p.r - v.r then
					targets[#targets+1] = v
				end
			end
		end
	end
	if memory.expand then
		local finished = true
		for _,v in pairs(memory.expand)do
			local v=G[v.n]
			if v and v.neutral then
				targets[#targets+1]=v
				finished = false
			end
		end
	end
	if control>.5 and control<.8 then
		local ships,total=ships,total
		local list={}
		for i=1,#data.neutral do list[i]=data.neutral[i]end
		repeat
			if sb_stats()>60 then break end
			local eeval,enemy=HUGE
			for _,v in pairs(data.eplanets)do
				local n=distance(v,home)
				if eeval>n then eeval,enemy=n,v end
			end
			if not enemy then
				local eeval=-HUGE
				for _,v in pairs(data.others)do
					local n=distance(v,home)
					if n>eeval then eeval,enemy=n,v end
				end
			end
			local dist,targ=HUGE
			for i=1,#list do local v=list[i]
				if ships-v.ships*1.5>total/2 then
					local d=-v.production
					if dist>d and d<distance(enemy,v)then
						dist,targ=d,v
					end
				end
			end
			if targ then
				targets[#targets+1]=targ
				ships,total=ships-targ.ships,total-targ.ships
				for i=1,#list do if list[i]==targ then list[i],list[#list]=list[#list]break end end
			end
		until not targ
	end
	local function tunnel(f, t)
		if not t then return end
		local ft = distance(f, t)
		for _,p in pairs(data.myteam) do
			if sb_stats() > 60 then break end
			local fp = distance(f, p)
			if fp < ft then
				local pt = distance(p, t)
				if p ~= f and pt < ft and (pt + fp - p.r*2) < ft then
					t, ft = p, fp
				end
			end
		end
		return t
	end
	local GetTarget=function(f)
		if recall then return end
		local teval,t=HUGE
		for _,v in pairs(targets)do
			local s=v.ships
			local dist=distance(f,v)
			if v.neutral then
				for _,x in pairs(data.myfleets)do if x~=f and x.target==v.n and distance(x, v) < dist then s=s-floor(x.ships)end end
			else
				local close=dist
				s=s+ceil(v.production*close/2000)
			end
			if floor(s)>=0 then
				local n = dist/10 + s - v.production/4
				if v.neutral then n = dist/10 end
				if teval>n then teval, t = n, v end
			end
			if sb_stats()>62 then break end
		end
		return t
	end
	local selected,maintarget,percent={}
	local danger,help={},{}
	local efleetmap = {}
	local imminent = {}
	for _, f in pairs(data.efleets) do
		local t = f.target
		if not efleetmap[t] then efleetmap[t] = {} end
		efleetmap[t][f.n] = true
		if distance(f, G[t]) < 100 then
			imminent[t] = true
		end
	end
	for ind,f in pairs(data.myplanets)do
		if sb_stats()>50 then break end
		local available,dist=floor(f.ships),HUGE
		for _, n in pairs(data.neutral) do
			if efleetmap[n.n] and distance(n, f) < 100 then
				if not efleetmap[f.n] then efleetmap[f.n] = {} end
				for v, _ in pairs(efleetmap[n.n]) do
					efleetmap[f.n][v] = true
				end
			end
		end
		if efleetmap[f.n] then
			for v, _ in pairs(efleetmap[f.n]) do
				local v = G[v]
				available = available - ceil(v.ships)
				dist = min(dist, distance(v, f) - f.r)
			end
		end
		if dist == HUGE then dist = 0 end
		local h=0
		for _,v in pairs(data.myfleets)do
			if sb_stats()>50 then break end
			if v.target==f.n then
				h=h+v.ships
			end
		end
		help[f]=h
		danger[f]=floor(available+f.production*dist/2000)
	end
	local low, assist = 0
	for _, v in pairs(data.myplanets) do
		if sb_stats() > 62 then break end
		local d = (danger[v] or v.ships) + (help[v] or 0)
		if d < low then low, assist = d, v end
	end
	for ind,f in pairs(stuff)do
		if sb_stats()>62 and ind~=1 then break end
		if f.is_planet then
			local available=danger[f]or f.ships
			if available>0 then
				local t0=GetTarget(f)
				local t=tunnel(f,t0)
				local low,t2=0
				for _,v in pairs(data.myplanets)do
					if sb_stats()>60 then break end
					local d=(danger[v]or v.ships)+(help[v]or 0)
					if d<low then low,t2=d,v end
				end
				local defend = defend
				--if t and t2 and distance(t2, t) + distance(f, t2)*.5 < distance(f, t) then defend = true end
				if t2 and imminent[t2.n] then defend = true end
				if t then
					if t2 and defend and not t.neutral and distance(t,f)>distance(t2,f)*1.5 and t2~=f then t=t2 end
				elseif t2 and defend and t2~=f then
					t=t2
				end
				if t then
					if not maintarget then maintarget=t end
					if maintarget~=t and t0 then
						if distance(f,t0)+10>distance(f,maintarget)+distance(maintarget,t0)-maintarget.r*2 then
							t=maintarget
						end
					end
					if maintarget==t then
						local a=floor(available*20/f.ships)*5
						if t.neutral then a=min(a,ceil((t.ships+1)*20/f.ships)*10)end
						if not percent then percent=a end
						if percent<=a then
							f.ships=f.ships-floor(ceil(a*20/f.ships)*f.ships/20+.5) 
							selected[#selected+1]=f.n
							if t == t2 then
								help[t] = (help[t] or 0) + f.ships
							end
						end
					end
				end
			end
		else
			local t=tunnel(f,GetTarget(f))
			local low,t2=0
			local targ=G[f.target]
			for _,v in pairs(data.myplanets)do
				if sb_stats()>60 then break end
				local d=(danger[v]or v.ships)+(help[v]or 0)
				if v==targ then d=d-f.ships end
				if d<low then low,t2=d,v end
			end
			local defend = defend
			--if t and t2 and distance(t2, t) + distance(f, t2)*.5 < distance(f, t) then defend = true end
			if t2 and imminent[t2.n] then defend = true end
			if t then
				if t2 and defend and not t.neutral and distance(t,f)>distance(t2,f)*1.5 then t=t2 end
			elseif t2 and defend then
				t=t2
			end
			if t and f.target ~= t.n then
				--if t.team ~= uteam or ((danger[t] or t.ships) + (help[t] or 0) - f.ships) > 0 then
					if not maintarget then maintarget=t end
					if maintarget==t then
						f.target=t.n
						selected[#selected+1]=f.n
						if t == t2 then
							help[t] = (help[t] or 0) + f.ships
						end
					end
				--end
			end
		end
	end
	if maintarget and #selected>0 then return send(percent,selected,maintarget)end
end