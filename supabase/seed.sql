-- No shared demo farm or credentials: POST /api/auth/demo creates isolated tenants.
insert into public.sources (id,title,url,excerpt,version) values
('fao-ipm','FAO — Integrated Pest Management','https://www.fao.org/pest-and-pesticide-management/ipm/integrated-pest-management/en/','IPM integrates biological, cultural, physical and chemical tools. Identify pests, monitor populations and consider economic thresholds before intervention.','2026-10-23 curated'),
('fao-soils','FAO — Soils Portal','https://www.fao.org/soils-portal/en/','Soil management decisions depend on soil properties, local conditions and observations; field inspection and soil analysis provide evidence for decisions.','2026-10-23 curated'),
('fao-water','FAO — Crop water information','https://www.fao.org/land-water/databases-and-software/crop-information/en/','Crop water requirements depend on growth stage, crop characteristics, climate and soil water. Verify local conditions before irrigation decisions.','2026-10-23 curated')
on conflict (id) do nothing;
