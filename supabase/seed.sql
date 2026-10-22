-- No shared demo farm or credentials: POST /api/auth/demo creates isolated tenants.
insert into public.sources (id,title,url,excerpt,version) values
('fao-ipm','FAO — Integrated Pest Management','https://www.fao.org/pest-and-pesticide-management/ipm/integrated-pest-management/en/','IPM integrates biological, cultural, physical and chemical tools. Identify pests, monitor populations and consider economic thresholds before intervention.','2026-10-23 curated'),
('fao-soils','FAO — Soils Portal','https://www.fao.org/soils-portal/en/','Soil management decisions depend on soil properties, local conditions and observations; field inspection and soil analysis provide evidence for decisions.','2026-10-23 curated'),
('fao-water','FAO — Irrigation Water Management: Crop water needs','https://www.fao.org/4/s2022e/s2022e02.htm','Crop water needs combine transpiration and evaporation, and vary with climate, crop type and growth stage. Water can come from rainfall, irrigation and storage in the root zone; local data should guide scheduling.','2026-10-23 curated')
on conflict (id) do update set title=excluded.title,url=excluded.url,excerpt=excluded.excerpt,version=excluded.version;
