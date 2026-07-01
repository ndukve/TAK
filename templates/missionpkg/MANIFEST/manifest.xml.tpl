<MissionPackageManifest version="2">
<Configuration>
<Parameter name="uid" value="{{ (.Env.TAK_SERVER_NAME | default "TAK Server") | strings.Slug }}-DEFAULT"/>
<Parameter name="name" value="{{ .Env.TAK_SERVER_NAME | default "TAK Server" }}"/>
<Parameter name="onReceiveDelete" value="false"/>
</Configuration>
<Contents>
<Content ignore="false" zipEntry="content/blueteam.pref"/>
<Content ignore="false" zipEntry="content/{{.Env.CLIENT_CERT_NAME}}.p12"/>
<Content ignore="false" zipEntry="content/truststore-root.p12"/>
<Content ignore="false" zipEntry="TAK_defaults.pref"/>
</Contents>
</MissionPackageManifest>
