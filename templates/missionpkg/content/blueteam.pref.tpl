<?xml version="1.0" encoding="ASCII" standalone="yes"?>
<preferences>
<preference version="1" name="cot_streams">
<entry key="count" class="class java.lang.Integer">{{if getenv "TAK_SERVER_ADDRESS_LAN" ""}}2{{else}}1{{end}}</entry>
<entry key="description0" class="class java.lang.String">{{ .Env.TAK_SERVER_NAME | default "TAK Server" }}</entry>
<entry key="enabled0" class="class java.lang.Boolean">true</entry>
<entry key="connectString0" class="class java.lang.String">{{.Env.TAK_SERVER_ADDRESS}}:8089:ssl</entry>
{{if getenv "TAK_SERVER_ADDRESS_LAN" ""}}<entry key="description1" class="class java.lang.String">{{ .Env.TAK_SERVER_NAME | default "TAK Server" }} (LAN)</entry>
<entry key="enabled1" class="class java.lang.Boolean">true</entry>
<entry key="connectString1" class="class java.lang.String">{{.Env.TAK_SERVER_ADDRESS_LAN}}:8089:ssl</entry>
{{else}}{{end}}</preference>
<preference version="1" name="com.atakmap.app_preferences">
<entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
<entry key="caLocation" class="class java.lang.String">truststore-root.p12</entry>
<entry key="caPassword" class="class java.lang.String">{{.Env.CA_PASS}}</entry>
<entry key="certificateLocation" class="class java.lang.String">{{.Env.CLIENT_CERT_NAME}}.p12</entry>
<entry key="clientPassword" class="class java.lang.String">{{.Env.CLIENT_CERT_PASSWORD}}</entry>
</preference>
</preferences>
