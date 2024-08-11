

var response = require('cfn-response');
exports.handler = function(event, context) { 
  var subnetsArray = event.ResourceProperties.subnets;
  var azSubnetsMap = new Map();
  for (var az of event.ResourceProperties.azList) {
    var subnetsMap = new Map();
    subnetsMap.set("private", subnetsArray.shift());
    subnetsMap.set("public", subnetsArray.shift());
    azSubnetsMap.set(az, subnetsMap);
    console.log(azSubnetsMap);
  }

  json_data = {
    "eu-west-3a": {
        "private": "10.192.0.0/24",
        "public":  "10.192.1.0/24"
        },
    "eu-west-3b": {
            "private": "10.192.2.0/24",
            "public":  "10.192.3.0/24"
            },
    "eu-west-3b": {
            "private": "10.192.2.0/24",
            "public":  "10.192.3.0/24"
            }
    };

  console.log(json_data);
  console.log(azSubnetsMap);
  console.log(JSON.stringify(azSubnetsMap));
  response.send(event, context, response.SUCCESS, {azSubnetsMap: JSON.stringify(json_data)});
};