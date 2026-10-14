/* Supabase Auth + PostgREST, without a build or CDN dependency. */
window.FernsCloud = (() => {
  const config = window.FERNSVILLA_SUPABASE;
  const key = config.publishableKey || localStorage.getItem('fernsvilla-public-key') || '';
  let session = null, role = null, revision = null, refreshing = null, ledgerVillas = [], legacyPayments = [];
  const directory = window.createVillaDirectory(request, config.villaMaster);
  const finance=window.createAssociationLedger(request,()=>!!session&&['admin','editor'].includes(role));
  const sessionKey = 'fernsvilla-supabase-session';
  try { session = JSON.parse(localStorage.getItem(sessionKey)); } catch {}
  function storeSession(value) { session = value; if (value) localStorage.setItem(sessionKey, JSON.stringify(value)); else localStorage.removeItem(sessionKey); }
  function publicKey(value) {
    if (value.startsWith('sb_publishable_')) return true;
    try { const payload = JSON.parse(atob(value.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))); return payload.role === 'anon'; } catch { return false; }
  }
  async function request(path, { method = 'GET', body, auth = true, prefer, accessToken } = {}) {
    if (!publicKey(key)) throw Error('Configure a valid public Supabase publishable or anon key.');
    if (auth && session && (session.expires_at || 0) <= Date.now()/1000 + 60) await refresh();
    const controller = new AbortController(); const timeout = setTimeout(()=>controller.abort(),15000);
    try {
      const headers = { apikey: key, 'Content-Type': 'application/json' };
      if (prefer) headers.Prefer = prefer;
      if (accessToken) headers.Authorization='Bearer '+accessToken;else if (auth && session) headers.Authorization = 'Bearer ' + session.access_token;
      const response = await fetch(config.url + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: controller.signal });
      const text = await response.text(); let data; try { data = JSON.parse(text); } catch { data = null; }
      if (!response.ok) {
        if (response.status === 401 && auth && data?.code !== '42501') storeSession(null);
        throw Error(data?.msg || data?.message || data?.error_description || (response.status===403?'Association access denied. Contact your administrator.':`Supabase request failed (${response.status}).`));
      }
      return data;
    } catch(error) { if (error.name==='AbortError') throw Error('Supabase request timed out. Please retry.'); throw error; } finally { clearTimeout(timeout); }
  }
  async function refresh() {
    if (!refreshing) refreshing = request('/auth/v1/token?grant_type=refresh_token',{method:'POST',auth:false,body:{refresh_token:session?.refresh_token}}).then(data=>storeSession({...data,recovery:!!session?.recovery,expires_at:Math.floor(Date.now()/1000)+data.expires_in})).catch(error=>{storeSession(null);throw error;}).finally(()=>refreshing=null);
    return refreshing;
  }
  function validate(data) { return data && ['villas','issues','team','resources','posts','payments'].every(name=>Array.isArray(data[name])); }
  async function load() {
    if (!session) throw Error('Sign in to access your association.');
    if(session.recovery)throw Error('Finish resetting your password before accessing association data.');
    const members = await request('/rest/v1/fernsvilla_members?select=role&user_id=eq.'+encodeURIComponent(session.user.id));
    role = members?.[0]?.role;
    if (!role) throw Error('Your account has not been added to the association. Ask the administrator to grant membership.');
    const rows = await request('/rest/v1/fernsvilla_state?select=data,revision&id=eq.1');
    if (!rows?.length) throw Error('Association database is not initialized. Run the supplied Supabase migration.');
    if (!validate(rows[0].data)) throw Error('Association data has an invalid format. Contact the administrator.');
    revision = rows[0].revision;
    const masterVillas = await directory.list();
    const financial=await finance.list();
    ledgerVillas = rows[0].data.villas;
    legacyPayments = rows[0].data.payments;
    return {...rows[0].data,...financial, villas: masterVillas.map(villa => {
      const balance = ledgerVillas.find(item => item.id === villa.id);
      return {...villa, due: villa.due ?? balance?.due ?? 0, paid: Number(balance?.paid ?? 0)};
    })};
  }
  async function save(data) {
    if (!session || !['admin','editor'].includes(role)) throw Error('Administrator or editor access is required to change association records.');
    const balances = new Map(ledgerVillas.map(villa => [villa.id, {id:villa.id,due:villa.due,paid:villa.paid}]));
    for (const villa of data.villas) balances.set(villa.id,{id:villa.id,due:villa.due,paid:villa.paid});
    const {dues,payments,allocations,...other}=data;
    const stored = {...other,payments:legacyPayments,villas:[...balances.values()]};
    const result = await request('/rest/v1/rpc/fernsvilla_save',{method:'POST',body:{expected_revision:revision,new_data:stored}});
    ledgerVillas = stored.villas;
    revision = result;
  }
  return {
    configured: publicKey(key), hasSession:()=>!!session, user:()=>session?.user,
    finance,
    async adminFeed(cursor=null) {
      if(!session||role!=='admin')throw Error('Administrator access is required to view the activity feed.');
      const params=new URLSearchParams({select:'*',order:'occurred_at.desc,id.desc',limit:'101'});
      if(cursor!==null){if(!/^\d+$/.test(String(cursor?.id))||!/^\d{4}-\d{2}-\d{2}T[\d:.]+(?:Z|[+-]\d{2}:\d{2})$/.test(cursor?.occurred_at)||Number.isNaN(Date.parse(cursor.occurred_at)))throw Error('Invalid activity cursor.');params.set('or',`(occurred_at.lt.${cursor.occurred_at},and(occurred_at.eq.${cursor.occurred_at},id.lt.${cursor.id}))`);}
      const rows=await request('/rest/v1/fernsvilla_audit_events?'+params);
      if(!Array.isArray(rows))throw Error('The activity feed returned an invalid response.');
      return {events:rows.slice(0,100),hasMore:rows.length>100};
    },
    saveVilla:async(villa,original)=>{if(!session||!['admin','editor'].includes(role))throw Error('Administrator or editor access is required to change villa records.');return directory.save(villa,original);},
    role:()=>role, canEdit:()=>!!session && ['admin','editor'].includes(role), load, save,
    setPublicKey(value) { if (!publicKey(value.trim())) throw Error('Use a public publishable or anon key, never a secret or service-role key.');localStorage.setItem('fernsvilla-public-key',value.trim()); },
    hasRecovery:()=>!!session?.recovery,
    clearRecovery(){if(session?.recovery){storeSession(null);role=null;revision=null;}},
    async sendPasswordReset(email){
      if(!email?.trim())throw Error('Enter your email address.');
      const redirect=config.passwordResetRedirect;
      if(!redirect||!redirect.startsWith('https://'))throw Error('Password recovery redirect is not configured.');
      await request('/auth/v1/recover?redirect_to='+encodeURIComponent(redirect),{method:'POST',auth:false,body:{email:email.trim()}});
    },
    async acceptRecovery(params){
      if(params.get('type')!=='recovery'||!params.get('access_token')||!params.get('refresh_token'))throw Error('This recovery link is incomplete. Request a new link.');
      const user=await request('/auth/v1/user',{auth:false,accessToken:params.get('access_token')});
      if(!user?.id)throw Error('This recovery link is invalid. Request a new link.');
      const expires=Number(params.get('expires_in'))||3600;
      role=null;revision=null;
      storeSession({access_token:params.get('access_token'),refresh_token:params.get('refresh_token'),user,recovery:true,expires_at:Math.floor(Date.now()/1000)+Math.max(1,Math.min(expires,3600))});
    },
    async setNewPassword(password){
      if(!session?.recovery)throw Error('Open a valid password recovery link first.');
      if(typeof password!=='string'||password.length<8)throw Error('Use at least 8 characters for your new password.');
      await request('/auth/v1/user',{method:'PUT',body:{password}});
      try{await request('/auth/v1/logout',{method:'POST'});}catch{}finally{storeSession(null);role=null;revision=null;}
    },
    async signIn(email,password) { const data=await request('/auth/v1/token?grant_type=password',{method:'POST',auth:false,body:{email,password}});storeSession({...data,expires_at:Math.floor(Date.now()/1000)+data.expires_in});return load(); },
    async signOut() { try { if(session) await request('/auth/v1/logout',{method:'POST'}); } finally { storeSession(null); role=null;revision=null; } }
  };
})();
