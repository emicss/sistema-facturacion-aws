export const esc = value => String(value ?? '—').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const label = key => key.replaceAll('_',' ').replace(/^./, c=>c.toUpperCase());
const currency = new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN',currencyDisplay:'narrowSymbol'});
export const money = value => currency.format(value);
export const badge = value => '<span class="badge" data-value="'+esc(value)+'">'+esc(value)+'</span>';
export const button = (action,title,id='') => '<button type="button" data-action="'+action+'" data-id="'+esc(id)+'">'+esc(title)+'</button>';
export const empty = message => '<p class="empty">'+esc(message)+'</p>';
export function table(headers, rows, message='Sin registros para mostrar.') {
  if (!rows.length) return empty(message);
  return '<div class="scroll"><table><thead><tr>'+headers.map(h=>'<th>'+esc(h)+'</th>').join('')+'</tr></thead><tbody>'+rows.map(row=>'<tr>'+row.map(v=>'<td>'+v+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>';
}
export const select = (name,title,options) => '<label>'+esc(title)+'<select required name="'+name+'">'+options.map(([v,t])=>'<option value="'+esc(v)+'">'+esc(t)+'</option>').join('')+'</select></label>';
export const choices = values => values.map(v=>[v,v]);
export const field = (name,title,type='text',attrs='') => '<label>'+esc(title)+'<input required name="'+name+'" type="'+type+'" '+attrs+'></label>';
export const pairs = data => '<dl>'+Object.entries(data).map(([k,v])=>'<div><dt>'+esc(label(k))+'</dt><dd>'+esc(v)+'</dd></div>').join('')+'</dl>';
export const json = data => '<pre>'+esc(JSON.stringify(data,null,2))+'</pre>';
export const dialog = document.querySelector('#dialog');
export function modal(title,html) {
  document.querySelector('#dialog-title').textContent=title;
  const body=document.querySelector('#dialog-body');
  body.innerHTML=html;
  if (!dialog.open) dialog.showModal();
  return body;
}
document.querySelector('#close').onclick=()=>dialog.close();
let timer;
export function notice(message) {
  const el=document.querySelector('#notice');
  el.textContent=message;
  clearTimeout(timer);
  timer=setTimeout(()=>el.textContent='',6000);
}
export function form(container, html, submit, handler) {
  container.innerHTML='<form>'+html+'<p class="error" role="alert"></p><button class="primary">'+esc(submit)+'</button></form>';
  const el=container.querySelector('form');
  el.onsubmit=async event=>{
    event.preventDefault();
    if (el.inert) return;
    const data=Object.fromEntries(new FormData(el));
    el.inert=true;
    const btn=el.querySelector('button.primary');
    btn.textContent='Procesando…';
    const inside=dialog.contains(el);
    if (inside) { dialog.oncancel=e=>e.preventDefault(); document.querySelector('#close').disabled=true; }
    try { await handler(data); }
    catch(error) { el.querySelector('.error').textContent=error.message; }
    finally {
      el.inert=false; btn.textContent=submit;
      if (inside) { dialog.oncancel=null; document.querySelector('#close').disabled=false; }
    }
  };
}
export const modalForm=(title, html, submit, handler)=>form(modal(title,''),html,submit,handler);
