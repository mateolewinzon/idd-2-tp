"""Genera el plan JMeter versionado; no requiere dependencias externas."""
from pathlib import Path
from xml.sax.saxutils import escape

def prop(name, value, kind='stringProp'):
    return f'<{kind} name="{name}">{escape(str(value))}</{kind}>'

def jsr(kind, name, script):
    tag = 'JSR223' + kind
    return f'<{tag} guiclass="TestBeanGUI" testclass="{tag}" testname="{name}" enabled="true">' + prop('scriptLanguage','groovy') + prop('cacheKey','true') + prop('script',script) + '</'+tag+'>'

origin = jsr('Sampler', 'origin', '''if (props.putIfAbsent('hito12.start', Long.toString(System.currentTimeMillis())) == null) {
 new File(props.get('phasefile')).text = props.get('hito12.start')
}''')
assertion = jsr('Assertion','integridad', '''def digest = java.security.MessageDigest.getInstance('SHA-256').digest(prev.getResponseData()).encodeHex().toString()
if (prev.getResponseCode() != '200' || digest != props.get('expected_sha')) {
 AssertionResult.setFailure(true)
 AssertionResult.setFailureMessage('HTTP o contenido incorrecto')
}''')
# Sólo datos de protocolo: la validación de contenido se hace fuera del tiempo HTTP.
xml = '''<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0" jmeter="5.6.3"><hashTree>
<TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="Fixture Hito 12" enabled="true">
<boolProp name="TestPlan.functional_mode">false</boolProp><elementProp name="TestPlan.user_defined_variables" elementType="Arguments"><collectionProp name="Arguments.arguments"/></elementProp>
</TestPlan><hashTree>
<ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Lectores" enabled="true">
<stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
<elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController" testname="Loop">
<boolProp name="LoopController.continue_forever">false</boolProp><intProp name="LoopController.loops">-1</intProp></elementProp>
<stringProp name="ThreadGroup.num_threads">${__P(users,1)}</stringProp>
<stringProp name="ThreadGroup.ramp_time">${__P(ramp,10)}</stringProp>
<boolProp name="ThreadGroup.scheduler">true</boolProp><stringProp name="ThreadGroup.duration">${__P(duration,70)}</stringProp>
</ThreadGroup><hashTree>
<OnceOnlyController guiclass="OnceOnlyControllerGui" testclass="OnceOnlyController" testname="Origen" enabled="true"/><hashTree>''' + origin + '''<hashTree/></hashTree>
<HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="fixture" enabled="true">
<stringProp name="HTTPSampler.domain">127.0.0.1</stringProp><stringProp name="HTTPSampler.port">${__P(port,58000)}</stringProp><stringProp name="HTTPSampler.protocol">http</stringProp><stringProp name="HTTPSampler.path">/fixture</stringProp><stringProp name="HTTPSampler.method">GET</stringProp><boolProp name="HTTPSampler.use_keepalive">true</boolProp><boolProp name="HTTPSampler.follow_redirects">false</boolProp><stringProp name="HTTPSampler.connect_timeout">${__P(timeout,10000)}</stringProp><stringProp name="HTTPSampler.response_timeout">${__P(timeout,10000)}</stringProp><elementProp name="HTTPsampler.Arguments" elementType="Arguments"><collectionProp name="Arguments.arguments"/></elementProp>
</HTTPSamplerProxy><hashTree>
<ConstantTimer guiclass="ConstantTimerGui" testclass="ConstantTimer" testname="Pausa" enabled="true"><stringProp name="ConstantTimer.delay">${__P(think,1000)}</stringProp></ConstantTimer><hashTree/>
''' + assertion + '''<hashTree/>
</hashTree></hashTree></hashTree></hashTree></jmeterTestPlan>'''
Path(__file__).with_name('fixture.jmx').write_text(xml)
