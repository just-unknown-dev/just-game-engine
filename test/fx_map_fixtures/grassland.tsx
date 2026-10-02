<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.10.2" name="grassland" tilewidth="32" tileheight="32" tilecount="32" columns="8">
 <image source="../tilesets/grassland.png" width="256" height="128"/>
 <tile id="1">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="2">
  <objectgroup draworder="index">
   <object id="1" x="16" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="3">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="16" height="16"/>
   <object id="2" x="16" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="4">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="5">
  <objectgroup draworder="index">
   <object id="1" type="oneWay" x="0" y="0" width="32" height="10"/>
  </objectgroup>
 </tile>
 <tile id="6">
  <properties>
   <property name="damage" type="float" value="1"/>
  </properties>
  <objectgroup draworder="index">
   <object id="1" type="hazard" x="2" y="18" width="28" height="14"/>
  </objectgroup>
 </tile>
 <tile id="7">
  <properties>
   <property name="bounce" type="float" value="1500"/>
  </properties>
  <objectgroup draworder="index">
   <object id="1" type="bouncy" x="0" y="12" width="32" height="20"/>
  </objectgroup>
 </tile>
 <tile id="8">
  <objectgroup draworder="index">
   <object id="1" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="9">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="16" height="16"/>
   <object id="2" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="10">
  <objectgroup draworder="index">
   <object id="1" x="16" y="0" width="16" height="16"/>
   <object id="2" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="11">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="16" height="16"/>
   <object id="2" x="16" y="0" width="16" height="16"/>
   <object id="3" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="12">
  <objectgroup draworder="index">
   <object id="1" x="0" y="32">
    <polygon points="0,0 32,-32 32,0"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="13">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0">
    <polygon points="0,0 32,32 0,32"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="14">
  <properties>
   <property name="crumbleDelay" type="float" value="0.4"/>
   <property name="respawnDelay" type="float" value="2.5"/>
  </properties>
  <objectgroup draworder="index">
   <object id="1" type="crumbling" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="15" type="water">
  <animation>
   <frame tileid="15" duration="250"/>
   <frame tileid="30" duration="250"/>
   <frame tileid="31" duration="250"/>
  </animation>
 </tile>
 <tile id="16">
  <objectgroup draworder="index">
   <object id="1" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="17">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="16" height="16"/>
   <object id="2" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="18">
  <objectgroup draworder="index">
   <object id="1" x="16" y="0" width="16" height="16"/>
   <object id="2" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="19">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="16" height="16"/>
   <object id="2" x="16" y="0" width="16" height="16"/>
   <object id="3" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="20">
  <objectgroup draworder="index">
   <object id="1" x="0" y="32">
    <polygon points="0,0 32,-16 32,0"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="21">
  <objectgroup draworder="index">
   <object id="1" x="0" y="16">
    <polygon points="0,0 32,-16 32,16 0,16"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="22">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0">
    <polygon points="0,0 32,16 32,32 0,32"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="23">
  <objectgroup draworder="index">
   <object id="1" x="0" y="16">
    <polygon points="0,0 32,16 0,16"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="24">
  <objectgroup draworder="index">
   <object id="1" x="0" y="16" width="16" height="16"/>
   <object id="2" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="25">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="16" height="16"/>
   <object id="2" x="0" y="16" width="16" height="16"/>
   <object id="3" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="26">
  <objectgroup draworder="index">
   <object id="1" x="16" y="0" width="16" height="16"/>
   <object id="2" x="0" y="16" width="16" height="16"/>
   <object id="3" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="27">
  <objectgroup draworder="index">
   <object id="1" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <wangsets>
  <wangset name="Ground" type="corner" tile="15">
   <wangcolor name="Ground" color="#6abe30" tile="27" probability="1"/>
   <wangcolor name="Air" color="#5fcde4" tile="0" probability="1"/>
   <wangtile tileid="0" wangid="0,2,0,2,0,2,0,2"/>
   <wangtile tileid="1" wangid="0,2,0,2,0,2,0,1"/>
   <wangtile tileid="2" wangid="0,1,0,2,0,2,0,2"/>
   <wangtile tileid="3" wangid="0,1,0,2,0,2,0,1"/>
   <wangtile tileid="8" wangid="0,2,0,1,0,2,0,2"/>
   <wangtile tileid="9" wangid="0,2,0,1,0,2,0,1"/>
   <wangtile tileid="10" wangid="0,1,0,1,0,2,0,2"/>
   <wangtile tileid="11" wangid="0,1,0,1,0,2,0,1"/>
   <wangtile tileid="16" wangid="0,2,0,2,0,1,0,2"/>
   <wangtile tileid="17" wangid="0,2,0,2,0,1,0,1"/>
   <wangtile tileid="18" wangid="0,1,0,2,0,1,0,2"/>
   <wangtile tileid="19" wangid="0,1,0,2,0,1,0,1"/>
   <wangtile tileid="24" wangid="0,2,0,1,0,1,0,2"/>
   <wangtile tileid="25" wangid="0,2,0,1,0,1,0,1"/>
   <wangtile tileid="26" wangid="0,1,0,1,0,1,0,2"/>
   <wangtile tileid="27" wangid="0,1,0,1,0,1,0,1"/>
  </wangset>
 </wangsets>
</tileset>