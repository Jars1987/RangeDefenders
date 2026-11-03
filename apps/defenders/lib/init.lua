local s=...
ui.bg("bg")
s[60][1]=ui.rect(0,0,320,3,{color="green"})
-- Widgets 1..13 are shared furniture; phase pools start at 14.
for i=1,8 do s[60][i+1]=ui.rect(1+i*73%316,6+i*47%190,2,2,{color="dim"}) end
-- Slots 61/63: sprite lines / row colors. Four columns at 5.5 px each;
-- six columns (33 px) between aliens. Slot 30 caches the drawn mask.
s[61]={" /\\ ","/oo\\","\\oo/","/||\\","|<>|","|__|","[=o]"," vv "}
s[63]={0xFF4040,"orange","yellow","pink"}
ui.hint("")
