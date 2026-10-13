/* Relational villa directory. Column names are supplied from the actual table schema. */
window.createVillaDirectory = (request, settings) => {
  const columns = settings?.columns;
  function checkConfig() {
    if (!settings?.table || !columns || !['key','id','name','type','phone'].every(key=>typeof columns[key]==='string'&&columns[key])) {
      throw Error('Configure the villaMaster column mapping in config.js using the existing Supabase table schema.');
    }
  }
  const base=()=>'/rest/v1/'+encodeURIComponent(settings.table);
  // PostgREST casts scalar filters to the column type. Quotes around 800 or true
  // become part of that value and fail numeric/boolean casts.
  // URLSearchParams handles transport escaping; scalar eq values need no
  // SQL-style quoting (including text containing punctuation or quotes).
  const literal=value=>String(value);
  const filter=(column,value)=>value==null?'is.null':'eq.'+literal(value);
  function map(row) {
    if(row[columns.key]==null||row[columns.id]==null)throw Error('villaMaster returned a record without its key or villa number.');
    const villa={id:String(row[columns.id]),name:String(row[columns.name]??''),type:String(row[columns.type]??''),phone:String(row[columns.phone]??''),_masterKey:row[columns.key],_masterRow:row};
    if(columns.due){villa.due=Number(row[columns.due]??0);if(!Number.isFinite(villa.due)||villa.due<0)throw Error('villaMaster contains an invalid monthly assessment.');}
    for(const key of ['area','street','resStatus','numRes','numKids','numVehicles','numPets','ownCCTV','ownPwrLine','oStatus','secPhone','priEmail','secEmail'])if(columns[key])villa[key]=row[columns[key]];
    if(String(villa.resStatus??'').trim().toLowerCase()==='under construction')villa.due=0;
    return villa;
  }
    const extras=['area','street','resStatus','numRes','numKids','numVehicles','numPets','ownCCTV','ownPwrLine','oStatus','secPhone','priEmail','secEmail'];
  async function list(){
    checkConfig();const result=[],size=500;
    const select=[...new Set(Object.values(columns).filter(Boolean))].join(',');
    for(let offset=0;;offset+=size){
      const params=new URLSearchParams({select,order:columns.key+'.asc',limit:String(size),offset:String(offset)});
      const rows=await request(base()+'?'+params);
      if(!Array.isArray(rows))throw Error('Could not read villaMaster directory records.');
      result.push(...rows.map(map));if(rows.length<size)break;
    }
    if(new Set(result.map(v=>v.id)).size!==result.length)throw Error('villaMaster contains duplicate villa numbers. Resolve them before recording dues.');
    return result;
  }
  async function save(villa,original){
    checkConfig();const body={};
    for(const key of ['id','name','type','phone','due',...extras])if(columns[key])body[columns[key]]=villa[key]===''||villa[key]==null?null:villa[key];
    if(columns.due&&String(villa.resStatus??'').trim().toLowerCase()==='under construction')body[columns.due]=0;
    let path=base(),method='POST';
    if(original){
      if(villa.id!==original.id)throw Error('Villa number cannot change because dues and payments reference it.');
      const params=new URLSearchParams();params.set(columns.key,'eq.'+literal(original._masterKey));
      // Compare original directory fields so stale edits fail instead of overwriting a newer record.
      for(const column of [...new Set(Object.values(columns).filter(Boolean))]){
        const old=original._masterRow[column];params.set(column,filter(column,old));
      }
      delete body[columns.id];delete body[columns.key];
      path+='?'+params;method='PATCH';
    }
    const rows=await request(path,{method,body,prefer:'return=representation'});
    if(Array.isArray(rows)&&rows.length===0&&original){
      const unchanged=await request(path);
      if(Array.isArray(unchanged)&&unchanged.length===1)throw Error('The villa was not saved. The record is unchanged but the update was blocked. Ask your administrator to check villaMaster UPDATE policies and grants.');
      throw Error('The villa was not saved. The record changed or is no longer accessible. Refresh the directory and retry.');
    }
    if(!Array.isArray(rows)||rows.length!==1)throw Error('The villa was not saved. Check villaMaster INSERT permissions and any database triggers.');
    return map(rows[0]);
  }
  return {list,save,hasAssessment:()=>!!columns?.due};
};
