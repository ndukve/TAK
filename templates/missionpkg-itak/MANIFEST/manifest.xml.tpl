<MissionPackageManifest version="2">
<Configuration>
<Parameter name="uid" value="{{ (.Env.TAK_SERVER_NAME | default "TAK Server") | strings.Slug }}-DEFAULT"/>
<Parameter name="name" value="{{ .Env.TAK_SERVER_NAME | default "TAK Server" }}"/>
<Parameter name="onReceiveDelete" value="false"/>
</Configuration>
<Contents>
<Content ignore="false" zipEntry="blueteam.pref"/>
<Content ignore="false" zipEntry="{{.Env.CLIENT_CERT_NAME}}.p12"/>
<Content ignore="false" zipEntry="truststore-root.p12"/>
<Content ignore="false" zipEntry="TAK_defaults.pref"/>
</Contents>
</MissionPackageManifest>
