try {
  Zabbix.log(4, '[Webhook] script value=' + value)
  // 添加日志记录输入值的详细内容
  Zabbix.log(4, '[Webhook] raw input value type: ' + typeof value + ', content: ' + value)
  
  var alert_url =
      'https://test.com/webhook/send?key=',
    params = {},
    request = new HttpRequest(),
    data = {},
    response
  
  // 使用 try-catch 单独处理输入JSON解析
  try {
    params = JSON.parse(value)
    Zabbix.log(4, '[Webhook] parsed params successfully')
  } catch(parseError) {
    throw 'Invalid input JSON format: ' + parseError + ', raw value: ' + value
  }
  
  data = {
    event_title: params.event_title,
    event_type: params.event_type || '告警',
    event_level: params.event_level,
    event_time: params.event_time,
    event_name: params.event_name,
    event_content: params.event_content,
  }

  if (params.event_app) {
    data.event_app = params.event_app
  }
  if (params.event_fingerprint) {
    data.event_fingerprint= params.event_fingerprint
  }
  if (params.HTTPProxy) {
    request.setProxy(params.HTTPProxy)
  }

  if (params.yunqiao_template_key) {
    alert_url = alert_url + params.yunqiao_template_key
  } else {
    throw 'yunqiao_template_key is required'
  }

  request.addHeader('Content-Type: application/json')
  Zabbix.log(4, '[Webhook] sending request to: ' + alert_url + ' with data: ' + JSON.stringify(data))
  
  var response = request.post(alert_url, JSON.stringify(data))
  Zabbix.log(4, '[Webhook] received response: ' + response)
  
  // 使用 try-catch 单独处理响应JSON解析
  var response_json = {}
  try {
    response_json = JSON.parse(response)
  } catch(parseError) {
    throw 'Invalid response JSON format: ' + parseError + ', raw response: ' + response
  }

  if (request.getStatus() != 200) {
    throw 'Response Status: ' + request.getStatus() + '\n' + response
  }
  if (response_json.err_code !== 'Com:Success') {
    throw 'Response Error: ' + response
  }
  return response
} catch (error) {
  Zabbix.Log(4, '[Webhook] notification failed: ' + error)
  throw 'Sending failed: ' + error
}