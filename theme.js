/* Apply before styles paint; follow the device until a theme is explicitly chosen. */
(()=>{
 const key='ferns-theme',root=document.documentElement,system=window.matchMedia('(prefers-color-scheme: dark)');
 const read=()=>{try{const value=localStorage.getItem(key);return ['light','dark'].includes(value)?value:null}catch{return null}};
 let preference=read();
 const icon=dark=>`<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${dark?'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>':'<path d="M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13Z"/>'}</svg>`;
 const dark=()=>root.dataset.theme==='dark';
 function sync(){root.dataset.theme=preference||(system.matches?'dark':'light');root.style.colorScheme=root.dataset.theme;document.querySelectorAll('[data-theme-toggle]').forEach(button=>{const label=`Switch to ${dark()?'light':'dark'} theme`;button.setAttribute('aria-label',label);button.setAttribute('title',label);button.setAttribute('aria-pressed',String(dark()));button.innerHTML=icon(dark());});}
 window.FernsTheme={button(){const label=`Switch to ${dark()?'light':'dark'} theme`;return `<button type="button" class="icon-btn theme-toggle" data-theme-toggle aria-label="${label}" title="${label}" aria-pressed="${dark()}">${icon(dark())}</button>`;}};
 document.addEventListener('click',event=>{if(!event.target.closest('[data-theme-toggle]'))return;preference=dark()?'light':'dark';try{localStorage.setItem(key,preference)}catch{}sync();});
 system.addEventListener('change',()=>{if(!preference)sync();});
 window.addEventListener('storage',event=>{if(event.key===key||event.key===null){preference=read();sync();}});
 sync();
})();
