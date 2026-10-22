import { z } from 'zod';
import type { Field, Weather } from '@agromax/contracts';
import { ApiFailure } from './domain.js';
const responseSchema=z.object({daily:z.object({time:z.array(z.string()),temperature_2m_min:z.array(z.number()),temperature_2m_max:z.array(z.number()),precipitation_sum:z.array(z.number())})});
export async function weather(field:Field,fetcher:typeof fetch=fetch):Promise<Weather>{
 const url=new URL('https://api.open-meteo.com/v1/forecast');url.search=new URLSearchParams({latitude:String(field.center.lat),longitude:String(field.center.lng),daily:'temperature_2m_max,temperature_2m_min,precipitation_sum',forecast_days:'5',timezone:'Europe/Moscow'}).toString();
 try{const r=await fetcher(url,{signal:AbortSignal.timeout(10000)});if(!r.ok)throw new Error();const {daily:d}=responseSchema.parse(await r.json());if(d.time.length!==d.temperature_2m_min.length||d.time.length!==d.temperature_2m_max.length||d.time.length!==d.precipitation_sum.length)throw new Error();return {fetchedAt:new Date().toISOString(),location:field.center,days:d.time.map((date,i)=>({date,minC:d.temperature_2m_min[i],maxC:d.temperature_2m_max[i],rainMm:d.precipitation_sum[i]})),source:'https://open-meteo.com/'};}catch{throw new ApiFailure(502,'WEATHER_UNAVAILABLE','Не удалось получить прогноз Open-Meteo');}
}
