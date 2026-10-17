/* Apply before styles paint; follow the device until a theme is explicitly chosen. */
(()=>{
 const key='ferns-theme',root=document.documentElement,system=window.matchMedia('(prefers-color-scheme: dark)');
 const read=()=>{try{const value=localStorage.getItem(key);return ['light','dark'].includes(value)?value:null}catch{return null}};
 const rainKey='ferns-rainy-day';
 const readRain=()=>{try{return localStorage.getItem(rainKey)==='true'}catch{return false}};
 let preference=read(),rainy=readRain();
 const rainIcon='<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 15a4 4 0 0 1-1-7.9 6 6 0 0 1 11.5-1.4A4.5 4.5 0 1 1 18 15H6Z"/><path d="m8 18-1 3m6-3-1 3m6-3-1 3"/></svg>';
 const icon=dark=>`<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${dark?'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>':'<path d="M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13Z"/>'}</svg>`;
 const dark=()=>root.dataset.theme==='dark';
 function sync(){root.dataset.rainyDay=String(rainy);root.dataset.theme=rainy?'dark':preference||(system.matches?'dark':'light');root.style.colorScheme=root.dataset.theme;document.querySelectorAll('[data-theme-toggle]').forEach(button=>{const label=`Switch to ${dark()?'light':'dark'} theme`;button.setAttribute('aria-label',label);button.setAttribute('title',label);button.setAttribute('aria-pressed',String(dark()));button.innerHTML=icon(dark());});document.querySelectorAll('[data-rain-toggle]').forEach(button=>button.setAttribute('aria-checked',String(rainy)));}
 window.FernsTheme={button(){const label=`Switch to ${dark()?'light':'dark'} theme`;return `<button type="button" class="icon-btn theme-toggle" data-theme-toggle aria-label="${label}" title="${label}" aria-pressed="${dark()}">${icon(dark())}</button><button type="button" class="icon-btn rainy-toggle" data-rain-toggle role="switch" aria-label="Rainy day theme" title="Rainy day theme" aria-checked="${rainy}">${rainIcon}<span class="rainy-switch" aria-hidden="true"></span></button>`;}};
 document.addEventListener('click',event=>{if(event.target.closest('[data-rain-toggle]')){rainy=!rainy;try{localStorage.setItem(rainKey,String(rainy))}catch{}sync();return;}if(!event.target.closest('[data-theme-toggle]'))return;rainy=false;try{localStorage.setItem(rainKey,'false')}catch{}preference=dark()?'light':'dark';try{localStorage.setItem(key,preference)}catch{}sync();});
 system.addEventListener('change',()=>{if(!preference)sync();});
 window.addEventListener('storage',event=>{if(event.key===key||event.key===rainKey||event.key===null){preference=read();rainy=readRain();sync();}});
 sync();
})();
