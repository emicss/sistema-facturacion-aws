import {request,transact,pending,session} from './api.js';
import {esc,money,badge,button,table,select,choices,field,pairs,json,modal,modalForm,dialog,notice,form} from './ui.js';

const replay='Esta transacción ya había sido procesada previamente. Mostrando el comprobante original sin duplicar cargos.';
const folio=f=>f.serie+'-'+f.folio;
function receipt(cfdi,message='') {
  const amounts=Object.fromEntries(Object.entries(cfdi.totales || {}).map(([k,v])=>[k,money(v)]));
  const body=modal('Comprobante '+folio(cfdi), (message?'<p>'+esc(message)+'</p>':'')+'<p>'+esc(cfdi.receptor?.razon_social)+' · CFDI '+esc(cfdi.version)+'</p>'+pairs(amounts)+button('copy','Copiar JSON')+json(cfdi));
  body.querySelector('button').onclick=async()=>{
    try {await navigator.clipboard.writeText(JSON.stringify(cfdi,null,2));notice('Comprobante copiado.')}
    catch {body.querySelector('button').textContent='Selecciona el JSON para copiarlo';}
  };
}
async function process(path,body,ctx) {
  let result;
  try { result=await transact(path,body); }
  catch(error) {
    if (ctx.active()) ctx.pending();
    throw error;
  }
  if (!ctx.active()) return;
  const owner=ctx.userId;
  await ctx.refresh();
  if (session()?.usuario.id_usuario!==owner) return;
  if (result.comprobante_cfdi) receipt(result.comprobante_cfdi,result.idempotente?replay:result.mensaje);
  else modal('Pago registrado', (result.idempotente?'<p>'+replay+'</p>':'')+pairs({folio:folio(result.factura),saldo_pendiente:money(result.factura.saldo_pendiente),estado_pago:result.factura.estado_pago}));
}
export function recover(container,ctx) {
  const intent=pending();
  container.innerHTML='';
  if (!intent) return;
  const issue=intent.path==='/facturas/emitir';
  if (issue?!ctx.issue:!ctx.finance) return;
  container.innerHTML='<aside class="pending"><strong>Operación por confirmar</strong><p>'+esc(issue?'Emisión de serie '+intent.body.serie+' para el cliente '+intent.body.id_cliente:'Pago de '+money(intent.body.monto_pagado)+' · '+intent.body.referencia_bancaria)+'</p>'+button('retry','Reintentar con la misma clave')+'</aside>';
  ctx.actions(container,()=>process(intent.path,intent.body,ctx));
}
export async function cart(el,ctx) {
  const [{items},clients]=await Promise.all([request('/carrito'),ctx.issue?request('/clientes'):Promise.resolve({clientes:[]})]);
  ctx.setCount(items);
  const sum=items.reduce((n,x)=>n+Number(x.precio_unitario)*Number(x.cantidad),0);
  el.innerHTML='<div class="section-head"><h2>Servicios seleccionados <small>'+items.length+'</small></h2>'+(items.length && ctx.issue?button('clear','Vaciar carrito'):'')+'</div>'+table(['Servicio','Cantidad','Precio MXN','Importe MXN',...(ctx.issue?['Acciones']:[])],items.map(x=>[esc(x.nombre_servicio),esc(x.cantidad),money(x.precio_unitario),money(x.precio_unitario*x.cantidad),...(ctx.issue?[button('remove','Quitar',x.id_servicio)]:[])]),'El carrito está vacío. Encuentra servicios en el catálogo.')+'<div id="checkout"></div>';
  if (items.length && ctx.issue) {
    form(el.querySelector('#checkout'),'<h2>Emisión de factura</h2>'+pairs({subtotal_estimado:money(sum)})+'<p>La emisión utiliza las tarifas vigentes y aplica el mayor descuento entre el del cliente y el de volumen (5 % desde $20,000 y 10 % desde $50,000).</p>'+select('id_cliente','Cliente receptor',[['','Selecciona un cliente'],...clients.clientes.map(x=>[x.id_cliente,x.razon_social+' · '+x.rfc+' · '+x.nivel_descuento+' ('+x.porcentaje_descuento+' %)'])])+select('serie','Serie',choices(['FAC','HON','NC'])),'Emitir y timbrar',data=>process('/facturas/emitir',{id_cliente:Number(data.id_cliente),serie:data.serie,usar_carrito_dynamo:true},ctx));
  }
  ctx.actions(el,async(action,id)=>{
    if (!ctx.issue) return;
    if (action==='remove') {
      await request('/carrito/items/'+id,'DELETE');await ctx.refresh();
    }
    if (action==='clear') modalForm('Vaciar carrito','<p>Se quitarán los '+items.length+' servicios seleccionados.</p>','Vaciar carrito',async()=>{
      try {for (const item of items) await request('/carrito/items/'+item.id_servicio,'DELETE');}
      finally {dialog.close(); await ctx.refresh();}
    });
  });
}
export async function invoices(el,ctx) {
  const {facturas}=await request('/facturas');
  el.innerHTML='<h2>Últimas facturas <small>'+facturas.length+'</small></h2>'+table(['Folio / cliente','Estado fiscal','Cobranza','Total MXN','Saldo MXN','Acciones'],facturas.map(f=>{
    const valid=f.estado_factura!=='CANCELADA';
    return ['<strong>'+esc(folio(f))+'</strong>'+esc(f.razon_social),badge(f.estado_factura),badge(f.estado_pago),money(f.total),money(f.saldo_pendiente),
      (f.uuid_fiscal?button('receipt','Comprobante',f.id_factura):'')+
      (valid && ctx.finance && Number(f.saldo_pendiente)>0?button('pay','Abonar',f.id_factura):'')+
      (valid && ctx.finance?button('cancel','Cancelar',f.id_factura):'')];
  }));
  ctx.actions(el,async(action,id)=>{
    const f=facturas.find(x=>String(x.id_factura)===id);
    const path='/facturas/'+id;
    if (action==='receipt') {
      const result=await request(path+'/timbrado');
      if (ctx.active()) receipt(result.comprobante_cfdi);
    }
    if (action==='pay' && ctx.finance) modalForm('Abonar a '+folio(f),'<p>Saldo pendiente <b>'+money(f.saldo_pendiente)+'</b></p>'+field('monto_pagado','Importe (MXN)','number','min="0.01" step="0.01" max="'+esc(f.saldo_pendiente)+'"')+select('metodo_pago','Método de pago',[['TRANSFERENCIA','Transferencia / SPEI'],...choices(['TARJETA','EFECTIVO','CHEQUE'])])+field('referencia_bancaria','Referencia bancaria','text','minlength="3" maxlength="80"'),'Registrar pago',data=>process(path+'/pagos',{...data,monto_pagado:Number(data.monto_pagado)},ctx));
    if (action==='cancel' && ctx.finance) modalForm('Cancelar '+folio(f),'<p>Se revertirán los pagos aplicados y el saldo quedará en cero.</p>'+field('motivo','Motivo fiscal','text','minlength="5" maxlength="250"'),'Confirmar cancelación',async data=>{
      await request(path+'/cancelar','POST',data);
      dialog.close();notice('Factura cancelada.');await ctx.refresh();
    });
  });
}
