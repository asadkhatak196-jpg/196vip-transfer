(() => {
  const cfg = window.VIP_SUPABASE_CONFIG || {};
  const ready = window.supabase && cfg.url && cfg.anonKey && !cfg.url.includes('YOUR_') && !cfg.anonKey.includes('YOUR_');
  const client = ready ? window.supabase.createClient(cfg.url, cfg.anonKey) : null;
  const $ = (id) => document.getElementById(id);
  const state = { user:null, profile:null, tab:'home', bookingId:null, bookings:[], offers:[], settings:null };
  $('year').textContent = new Date().getFullYear();
  const esc = (v='') => String(v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = v => `SAR ${Number(v || 0).toFixed(2)}`;
  const date = v => v ? new Date(v).toLocaleString() : 'Not specified';
  const statusClass = s => s === 'approved' || s === 'accepted' || s === 'completed' ? 'good' : s === 'disabled' || s === 'rejected' || s === 'cancelled' ? 'bad' : 'warn';
  function note(id, msg, type='') { const el=$(id); if(el){el.textContent=msg;el.className='status '+type;} }
  function card(title, body, extra='') { return `<article class="card"><h3>${title}</h3>${body}${extra}</article>`; }
  function empty(msg) { return `<div class="empty">${esc(msg)}</div>`; }
  function setView(authenticated) { $('auth-view').classList.toggle('hidden', authenticated); $('app-view').classList.toggle('hidden', !authenticated); $('signout').classList.toggle('hidden', !authenticated); }
  function tabsForRole() {
    const common = [{id:'home',label:'Overview'},{id:'profile',label:'Profile'}];
    if(state.profile?.role === 'admin') return [...common,{id:'admin',label:'Admin panel'},{id:'chat',label:'Messages'}];
    if(state.profile?.role === 'driver') return [...common,{id:'driver',label:'Driver jobs'},{id:'chat',label:'Messages'}];
    return [...common,{id:'book',label:'New booking'},{id:'trips',label:'My bookings'},{id:'driverapply',label:'Become a driver'},{id:'chat',label:'Messages'}];
  }
  function renderTabs() {
    $('tabs').innerHTML=tabsForRole().map(t=>`<button class="tab ${state.tab===t.id?'active':''}" data-tab="${t.id}">${t.label}</button>`).join('');
    $('tabs').querySelectorAll('[data-tab]').forEach(b=>b.addEventListener('click',()=>{state.tab=b.dataset.tab;render();}));
  }
  async function loadProfile() {
    const {data,error}=await client.from('vip_profiles').select('*').eq('id',state.user.id).single();
    if(error) throw error; state.profile=data;
  }
  async function refresh() {
    if(!client || !state.user) return;
    try { await loadProfile(); $('user-email').textContent=state.user.email; $('welcome-title').textContent=`Hello${state.profile.full_name?' '+state.profile.full_name:''}`; setView(true); render(); }
    catch(e){ note('auth-status',`Could not load your account: ${e.message}`,'error'); }
  }
  function render() {
    renderTabs();
    const role=state.profile?.role;
    if(state.tab==='home') return renderHome();
    if(state.tab==='profile') return renderProfile();
    if(state.tab==='book' && role==='customer') return renderBook();
    if(state.tab==='trips' && role==='customer') return renderTrips();
    if(state.tab==='driverapply' && role==='customer') return renderDriverApplication();
    if(state.tab==='driver' && role==='driver') return renderDriver();
    if(state.tab==='admin' && role==='admin') return renderAdmin();
    if(state.tab==='chat') return renderChat();
    state.tab='home'; render();
  }
  function renderHome() {
    const role=state.profile.role;
    const descriptions={customer:'Create a ride request, compare driver offers, and accept the ride that works for you.',driver:'Review available bookings, send offers, and chat after a customer accepts your offer.',admin:'Manage driver applications, booking activity, and offer settings.'};
    $('view-content').innerHTML=card(`${role[0].toUpperCase()+role.slice(1)} dashboard`,`<p>${descriptions[role]}</p><p><span class="pill">${esc(role)}</span> <span class="pill">${esc(state.user.email)}</span></p>`)+card('Support',`<p>For help with your account or booking, contact:</p><p><a href="mailto:Limuzin@196vip.si">Limuzin@196vip.si</a></p>`);
  }
  function renderProfile() {
    $('view-content').innerHTML=`<section class="card"><h2>Account profile</h2><form id="profile-form" class="form-grid"><label>Full name<input name="full_name" maxlength="120" value="${esc(state.profile.full_name||'')}"></label><label>Email address<input value="${esc(state.user.email)}" disabled></label><label>Account type<input value="${esc(state.profile.role)}" disabled></label><div class="full"><button class="button">Save profile</button><p id="profile-status" class="status"></p></div></form></section>`;
    $('profile-form').addEventListener('submit',async e=>{e.preventDefault();const full_name=new FormData(e.target).get('full_name').trim();const {error}=await client.from('vip_profiles').update({full_name}).eq('id',state.user.id);note('profile-status',error?error.message:'Profile updated.',error?'error':'ok');if(!error){state.profile.full_name=full_name;$('welcome-title').textContent=`Hello${full_name?' '+full_name:''}`;}});
  }
  function renderBook() {
    $('view-content').innerHTML=`<section class="card"><h2>Request a ride</h2><p class="muted">Enter your pickup and destination. Drivers can send you price offers.</p><form id="booking-form" class="form-grid"><label>Pickup location<input name="pickup" required maxlength="500" placeholder="Airport, hotel, address"></label><label>Destination<input name="destination" required maxlength="500" placeholder="Where would you like to go?"></label><label>Pickup date and time<input name="pickup_at" type="datetime-local"></label><label>Vehicle category<select name="category"><option>Comfort</option><option>Business</option><option>VIP</option></select></label><label>Passengers<input name="passengers" type="number" min="1" max="20" value="1" required></label><label class="full">Additional details<textarea name="notes" maxlength="1000" placeholder="Flight number, luggage, child seat, or other details"></textarea></label><div class="full"><button class="button">Submit booking request</button><p id="booking-status" class="status"></p></div></form></section>`;
    $('booking-form').addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(e.target);const payload={customer_id:state.user.id,pickup:f.get('pickup').trim(),destination:f.get('destination').trim(),pickup_at:f.get('pickup_at')?new Date(f.get('pickup_at')).toISOString():null,category:f.get('category'),passengers:Number(f.get('passengers')),notes:f.get('notes').trim(),status:'open'};const {error}=await client.from('vip_bookings').insert(payload);note('booking-status',error?`Could not submit booking: ${error.message}`:'Your booking request has been submitted. You can view driver offers under My bookings.',error?'error':'ok');if(!error)e.target.reset();});
  }
  async function renderTrips() {
    $('view-content').innerHTML='<div class="muted">Loading your bookings…</div>';
    const {data,error}=await client.from('vip_bookings').select('*').eq('customer_id',state.user.id).order('created_at',{ascending:false});
    if(error){$('view-content').innerHTML=empty(error.message);return;} state.bookings=data||[];
    if(!data.length){$('view-content').innerHTML=empty('You have not submitted any bookings yet.');return;}
    const parts=[];
    for(const b of data){const {data:offers}=await client.from('vip_offers').select('id,price_sar,status,created_at,driver_id,vehicle_id').eq('booking_id',b.id).order('created_at');let offerHtml='';
      for(const o of offers||[]){const {data:v}=o.vehicle_id?await client.from('vip_vehicles').select('model,plate,category').eq('id',o.vehicle_id).maybeSingle():{data:null};offerHtml+=`<div class="card"><div class="section-head"><strong>Driver offer</strong><span class="pill ${statusClass(o.status)}">${esc(o.status)}</span></div><div class="price">${money(o.price_sar)}</div><p>${esc(v?.category||'Vehicle')} · ${esc(v?.model||'Details pending')} · ${esc(v?.plate||'')}</p>${o.status==='pending'&&b.status==='open'?`<button class="button success" data-accept="${o.id}">Accept this offer</button>`:''}</div>`;}
      parts.push(`<section class="card"><div class="section-head"><h2>Booking</h2><span class="pill ${statusClass(b.status)}">${esc(b.status)}</span></div><p><b>Pickup:</b> ${esc(b.pickup)}</p><p><b>Destination:</b> ${esc(b.destination)}</p><p><b>Pickup time:</b> ${date(b.pickup_at)}</p><p><b>Vehicle:</b> ${esc(b.category)} · ${b.passengers} passenger(s)</p><h3>Driver offers</h3>${offerHtml||empty('No driver offers yet. Please check again later.')}</section>`);
    }
    $('view-content').innerHTML=parts.join('');$('view-content').querySelectorAll('[data-accept]').forEach(btn=>btn.addEventListener('click',async()=>{btn.disabled=true;const {error}=await client.rpc('vip_accept_offer',{p_offer_id:btn.dataset.accept});if(error)alert(error.message);else alert('Offer accepted. You can now chat with your driver.');renderTrips();}));
  }
  async function renderDriverApplication() {
    const {data:app}=await client.from('vip_driver_applications').select('*').eq('driver_id',state.user.id).maybeSingle();
    if(app){$('view-content').innerHTML=card('Driver application',`<p>Status: <span class="pill ${statusClass(app.status)}">${esc(app.status)}</span></p><p>Vehicle: ${esc(app.vehicle_category)} · ${esc(app.vehicle_model)}</p><p>Plate: ${esc(app.vehicle_plate||'Not provided')}</p><p class="muted">${esc(app.notes||'')}</p>`);return;}
    $('view-content').innerHTML=`<section class="card"><h2>Apply to become a driver</h2><p class="muted">Submit your vehicle details. An administrator must review and approve your application before you can send offers.</p><form id="driver-form" class="form-grid"><label>Vehicle category<select name="vehicle_category"><option>Comfort</option><option>Business</option><option>VIP</option></select></label><label>Vehicle model<input name="vehicle_model" required maxlength="120" placeholder="Make and model"></label><label>Vehicle year<input name="vehicle_year" type="number" min="1990" max="2035"></label><label>Vehicle plate number<input name="vehicle_plate" maxlength="30"></label><label class="full">Vehicle photo URL<input name="vehicle_photo_url" type="url" placeholder="https://…"></label><label class="full">Additional information<textarea name="notes" maxlength="1000"></textarea></label><div class="full"><button class="button">Submit driver application</button><p id="driver-status" class="status"></p></div></form></section>`;
    $('driver-form').addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(e.target);const payload={driver_id:state.user.id,vehicle_category:f.get('vehicle_category'),vehicle_model:f.get('vehicle_model').trim(),vehicle_year:f.get('vehicle_year')?Number(f.get('vehicle_year')):null,vehicle_plate:f.get('vehicle_plate').trim(),vehicle_photo_url:f.get('vehicle_photo_url').trim()||null,notes:f.get('notes').trim(),status:'pending'};const {error}=await client.from('vip_driver_applications').insert(payload);note('driver-status',error?error.message:'Application submitted. You will be able to send offers after approval.',error?'error':'ok');if(!error)renderDriverApplication();});
  }
  async function renderDriver() {
    const [{data:app},{data:vehicles},{data:bookings},{data:settings}] = await Promise.all([client.from('vip_driver_applications').select('*').eq('driver_id',state.user.id).maybeSingle(),client.from('vip_vehicles').select('*').eq('driver_id',state.user.id),client.from('vip_bookings').select('*').eq('status','open').order('created_at',{ascending:false}),client.from('vip_settings').select('*').eq('id',1).single()]);
    state.settings=settings;
    if(!app||app.status!=='approved'){ $('view-content').innerHTML=empty('Your driver account is not approved or has been disabled. Please contact support.');return; }
    let html=`<section class="card"><div class="section-head"><h2>Driver workspace</h2><span class="pill good">Approved</span></div><p>Offer feature: <span class="pill ${settings?.offers_enabled?'good':'bad'}">${settings?.offers_enabled?'Enabled':'Disabled by administrator'}</span></p><form id="vehicle-form" class="form-grid"><label>Vehicle category<select name="category"><option>Comfort</option><option>Business</option><option>VIP</option></select></label><label>Vehicle model<input name="model" required placeholder="Make and model"></label><label>Plate number<input name="plate" maxlength="30"></label><label>Vehicle photo URL<input name="photo_url" type="url" placeholder="https://…"></label><div class="full"><button class="button secondary">Add vehicle</button><p id="vehicle-status" class="status"></p></div></form><p><b>Your vehicles:</b> ${(vehicles||[]).map(v=>`${esc(v.category)} ${esc(v.model)} (${esc(v.plate||'No plate')})`).join(' · ')||'No vehicles added yet'}</p></section>`;
    if(!settings?.offers_enabled) html+=empty('Driver offers are currently turned off by the administrator.');
    else if(!bookings?.length) html+=empty('There are no open booking requests right now.');
    else {html+='<h2>Open booking requests</h2><div class="grid">';for(const b of bookings){const {data:existing}=await client.from('vip_offers').select('id').eq('booking_id',b.id).eq('driver_id',state.user.id).maybeSingle();html+=`<article class="card"><span class="pill">${esc(b.category)}</span><h3>${esc(b.pickup)} → ${esc(b.destination)}</h3><p>Pickup: ${date(b.pickup_at)}</p><p>Passengers: ${b.passengers}</p><p>${esc(b.notes||'No extra details')}</p>${existing?'<p class="muted">You have already sent an offer.</p>':`<form class="offer-form stack" data-booking="${b.id}"><label>Your price (SAR)<input name="price_sar" type="number" min="1" step="0.01" required></label><label>Your vehicle<select name="vehicle_id"><option value="">Select vehicle (optional)</option>${(vehicles||[]).map(v=>`<option value="${v.id}">${esc(v.category)} · ${esc(v.model)} · ${esc(v.plate||'')}</option>`).join('')}</select></label><button class="button">Send price offer</button><p class="status"></p></form>`}</article>`;}html+='</div>';}
    $('view-content').innerHTML=html;
    $('vehicle-form').addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(e.target);const {error}=await client.from('vip_vehicles').insert({driver_id:state.user.id,category:f.get('category'),model:f.get('model').trim(),plate:f.get('plate').trim(),photo_url:f.get('photo_url').trim()||null});note('vehicle-status',error?error.message:'Vehicle added.',error?'error':'ok');if(!error)renderDriver();});
    $('view-content').querySelectorAll('.offer-form').forEach(form=>form.addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(form);const payload={booking_id:form.dataset.booking,driver_id:state.user.id,price_sar:Number(f.get('price_sar')),vehicle_id:f.get('vehicle_id')||null,status:'pending'};const {error}=await client.from('vip_offers').insert(payload);form.querySelector('.status').textContent=error?error.message:'Offer sent to customer.';if(!error)renderDriver();}));
  }
  async function renderAdmin() {
    const [{data:profiles,error:pErr},{data:apps,error:aErr},{data:bookings,error:bErr},{data:settings,error:sErr}]=await Promise.all([client.from('vip_profiles').select('*').order('created_at',{ascending:false}),client.from('vip_driver_applications').select('*').order('created_at',{ascending:false}),client.from('vip_bookings').select('*').order('created_at',{ascending:false}).limit(100),client.from('vip_settings').select('*').eq('id',1).single()]);
    if(pErr||aErr||bErr||sErr){$('view-content').innerHTML=empty(`Admin data error: ${(pErr||aErr||bErr||sErr).message}`);return;}
    state.settings=settings;
    let html=`<section class="card"><div class="section-head"><h2>System settings</h2><span class="pill">Admin</span></div><label><span>Allow drivers to send price offers</span><select id="offers-enabled"><option value="true" ${settings.offers_enabled?'selected':''}>Enabled</option><option value="false" ${!settings.offers_enabled?'selected':''}>Disabled</option></select></label><p class="muted">When disabled, drivers cannot send new offers.</p><p id="settings-status" class="status"></p></section>`;
    html+='<section><h2>Driver applications</h2><div class="grid">';
    if(!apps?.length)html+=empty('No driver applications yet.');
    for(const a of apps||[]){const profile=(profiles||[]).find(p=>p.id===a.driver_id);html+=`<article class="card"><div class="section-head"><h3>${esc(profile?.full_name||profile?.email||'Driver')}</h3><span class="pill ${statusClass(a.status)}">${esc(a.status)}</span></div><p>${esc(a.vehicle_category)} · ${esc(a.vehicle_model)} · ${esc(a.vehicle_year||'')}</p><p>Plate: ${esc(a.vehicle_plate||'Not provided')}</p><p>${esc(a.notes||'')}</p><div class="actions"><button class="button success" data-driver-status="approved" data-driver="${a.driver_id}">Approve / Enable</button><button class="button danger" data-driver-status="disabled" data-driver="${a.driver_id}">Disable</button></div></article>`;}
    html+='</div></section><section><h2>Customer and driver accounts</h2><div class="grid">';
    for(const p of profiles||[])html+=`<article class="card"><b>${esc(p.full_name||'No name')}</b><p>${esc(p.email||'')}</p><span class="pill">${esc(p.role)}</span></article>`;
    html+='</div></section><section><h2>Recent bookings</h2><div class="grid">';
    for(const b of bookings||[]){const p=(profiles||[]).find(x=>x.id===b.customer_id);html+=`<article class="card"><span class="pill ${statusClass(b.status)}">${esc(b.status)}</span><h3>${esc(b.pickup)} → ${esc(b.destination)}</h3><p>Customer: ${esc(p?.email||'Unknown')}</p><p>${date(b.pickup_at)} · ${esc(b.category)} · ${b.passengers} passenger(s)</p></article>`;}
    if(!bookings?.length)html+=empty('No bookings yet.');html+='</div></section>';
    $('view-content').innerHTML=html;
    $('offers-enabled').addEventListener('change',async e=>{const {error}=await client.from('vip_settings').update({offers_enabled:e.target.value==='true'}).eq('id',1);note('settings-status',error?error.message:'Settings updated.',error?'error':'ok');});
    $('view-content').querySelectorAll('[data-driver-status]').forEach(btn=>btn.addEventListener('click',async()=>{btn.disabled=true;const {error}=await client.rpc('vip_admin_set_driver_status',{p_driver_id:btn.dataset.driver,p_status:btn.dataset.driverStatus});if(error)alert(error.message);else alert('Driver status updated.');renderAdmin();}));
  }
  async function renderChat() {
    $('view-content').innerHTML='<div class="muted">Loading conversations…</div>';
    let bookings=[];
    if(state.profile.role==='admin') {
      const {data,error}=await client.from('vip_bookings').select('id,pickup,destination,status').order('created_at',{ascending:false}).limit(100);
      if(error){$('view-content').innerHTML=empty(error.message);return;} bookings=data||[];
    } else if(state.profile.role==='customer') {
      const {data,error}=await client.from('vip_bookings').select('id,pickup,destination,status').eq('customer_id',state.user.id).eq('status','accepted').order('created_at',{ascending:false});
      if(error){$('view-content').innerHTML=empty(error.message);return;} bookings=data||[];
    } else {
      const {data:offers,error}=await client.from('vip_offers').select('booking_id').eq('driver_id',state.user.id).eq('status','accepted');
      if(error){$('view-content').innerHTML=empty(error.message);return;}
      const ids=(offers||[]).map(o=>o.booking_id);
      if(ids.length){const {data,error:e}=await client.from('vip_bookings').select('id,pickup,destination,status').in('id',ids);if(e){$('view-content').innerHTML=empty(e.message);return;}bookings=data||[];}
    }
    state.chatBookings=bookings;
    if(!bookings.some(b=>b.id===state.bookingId)) state.bookingId=bookings[0]?.id||null;
    $('view-content').innerHTML=`<section class="card"><h2>Messages</h2><p class="muted">In-app chat is available for the customer and the driver after an offer is accepted.</p><label>Booking<select id="chat-booking"><option value="">Select a booking</option>${bookings.map(b=>`<option value="${b.id}" ${state.bookingId===b.id?'selected':''}>${esc(b.pickup)} → ${esc(b.destination)} (${esc(b.status)})</option>`).join('')}</select></label><div id="chat-area"></div></section>`;
    $('chat-booking').addEventListener('change',()=>{state.bookingId=$('chat-booking').value;loadChatMessages();});
    await loadChatMessages();
  }
  async function loadChatMessages() {
    const area=$('chat-area');if(!area)return;if(!state.bookingId){area.innerHTML=empty('There are no conversations available yet.');return;}
    const {data,error}=await client.from('vip_messages').select('*').eq('booking_id',state.bookingId).order('created_at',{ascending:true}).limit(200);
    if(error){area.innerHTML=empty(error.message);return;}showChatMessages(data||[]);
  }
  function showChatMessages(msgs) {
    const area=$('chat-area');if(!area)return;if(!state.bookingId){area.innerHTML=empty('Choose a booking to open the conversation.');return;}
    const rows=msgs.filter(m=>m.booking_id===state.bookingId);area.innerHTML=`<div class="message-list">${rows.map(m=>`<div class="message ${m.sender_id===state.user.id?'mine':''}">${esc(m.body)}<small>${date(m.created_at)}</small></div>`).join('')||'<p class="muted">No messages yet.</p>'}</div><form id="chat-form" class="stack"><label>Message<textarea name="body" maxlength="2000" required></textarea></label><button class="button">Send message</button><p id="chat-status" class="status"></p></form>`;
    $('chat-form').addEventListener('submit',async e=>{e.preventDefault();const body=new FormData(e.target).get('body').trim();const {error}=await client.from('vip_messages').insert({booking_id:state.bookingId,sender_id:state.user.id,body});note('chat-status',error?error.message:'Message sent.',error?'error':'ok');if(!error)loadChatMessages();});
  }
  $('otp-form').addEventListener('submit',async e=>{e.preventDefault();if(!client){note('auth-status','Setup required: add your Supabase Project URL and Publishable API Key to config.js.','error');return;}const email=$('email').value.trim();$('send-code').disabled=true;const {error}=await client.auth.signInWithOtp({email,options:{shouldCreateUser:true}});$('send-code').disabled=false;if(error){note('auth-status',error.message,'error');return;}$('verify-form').classList.remove('hidden');note('auth-status','A verification code has been requested. Check your inbox and Spam or Junk folder.','ok');});
  $('verify-form').addEventListener('submit',async e=>{e.preventDefault();if(!client)return;const email=$('email').value.trim(),token=$('otp').value.trim();const {error}=await client.auth.verifyOtp({email,token,type:'email'});if(error){note('auth-status',error.message,'error');return;}note('auth-status','Email verified. Signing you in…','ok');});
  $('signout').addEventListener('click',async()=>{if(client)await client.auth.signOut();state.user=null;state.profile=null;setView(false);});
  $('refresh').addEventListener('click',refresh);
  if(!client){note('auth-status','Setup required: add your Supabase Project URL and Publishable API Key to config.js.','error');}
  else {client.auth.onAuthStateChange((_event,session)=>{state.user=session?.user||null;if(state.user)refresh();else setView(false);});client.auth.getSession().then(({data})=>{state.user=data.session?.user||null;if(state.user)refresh();else setView(false);});}
})();
