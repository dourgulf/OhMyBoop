// Locate the first JSON syntax error after the native JSON.parse has failed.
// Offsets are JavaScript string offsets (UTF-16), matching NSTextView ranges.
exports.diagnose = function (text) {
  var i = 0;
  function fail(message, offset) { throw { message: message, offset: offset == null ? i : offset }; }
  function space() { while (/[\x20\t\r\n]/.test(text.charAt(i)) && i < text.length) i++; }
  function string() {
    i++;
    while (i < text.length) {
      var c = text.charAt(i);
      if (c === '"') { i++; return; }
      if (c.charCodeAt(0) < 32) fail("字符串中不能直接包含换行或控制字符，请使用转义符");
      if (c === '\\') {
        i++;
        if (i === text.length) fail("转义序列不完整");
        c = text.charAt(i);
        if (c === 'u') {
          for (var n = 0; n < 4; n++) {
            i++;
            if (!/[0-9a-fA-F]/.test(text.charAt(i)) || i === text.length) fail("Unicode 转义需要四位十六进制数字");
          }
        } else if ('"\\/bfnrt'.indexOf(c) < 0) fail("无效的字符串转义");
      }
      i++;
    }
    fail("字符串缺少结束双引号");
  }
  function number() {
    if (text.charAt(i) === '-') i++;
    if (text.charAt(i) === '0') {
      i++;
      if (/[0-9]/.test(text.charAt(i)) && i < text.length) fail("数字不能包含前导零");
    } else {
      if (!/[1-9]/.test(text.charAt(i)) || i === text.length) fail("此处需要数字");
      while (/[0-9]/.test(text.charAt(i)) && i < text.length) i++;
    }
    if (text.charAt(i) === '.') {
      i++;
      if (!/[0-9]/.test(text.charAt(i)) || i === text.length) fail("小数点后需要数字");
      while (/[0-9]/.test(text.charAt(i)) && i < text.length) i++;
    }
    if (text.charAt(i) === 'e' || text.charAt(i) === 'E') {
      i++;
      if (text.charAt(i) === '+' || text.charAt(i) === '-') i++;
      if (!/[0-9]/.test(text.charAt(i)) || i === text.length) fail("指数部分需要数字");
      while (/[0-9]/.test(text.charAt(i)) && i < text.length) i++;
    }
  }
  function value(depth) {
    space();
    if (depth > 512) fail("嵌套过深，无法进一步定位错误");
    var c = text.charAt(i);
    if (i === text.length) fail("缺少 JSON 值");
    if (c === '"') return string();
    if (c === '-' || /[0-9]/.test(c)) return number();
    if (c === '{' || c === '[') {
      var object = c === '{', end = object ? '}' : ']';
      i++; space();
      if (text.charAt(i) === end) { i++; return; }
      while (true) {
        if (object) {
          if (text.charAt(i) !== '"') fail("对象属性名必须使用双引号");
          string(); space();
          if (text.charAt(i) !== ':') fail("属性名后缺少冒号 :");
          i++;
        }
        value(depth + 1);
        var valueEnd = i;
        space();
        if (text.charAt(i) === end) { i++; return; }
        if (i === text.length) fail("缺少结束符 " + end);
        if (text.charAt(i) === '，') fail("使用了中文逗号“，”，请改为英文逗号“,”");
        if (text.charAt(i) !== ',') {
          var next = text.charAt(i);
          var startsNextItem = object ? next === '"' || next === "'" : /[\[\{"'0-9tfn-]/.test(next);
          if (startsNextItem) fail("此处缺少逗号 ,（上一项之后）", valueEnd);
          fail("此处需要逗号 , 或结束符 " + end);
        }
        var commaOffset = i;
        i++; space();
        if (text.charAt(i) === end) fail("最后一项后不能有多余的逗号", commaOffset);
      }
    }
    var literal = c === 't' ? 'true' : c === 'f' ? 'false' : c === 'n' ? 'null' : null;
    if (literal) {
      for (var j = 0; j < literal.length; j++, i++) {
        if (text.charAt(i) !== literal.charAt(j)) fail("此处应为 " + literal);
      }
      return;
    }
    if (c === "'") fail("JSON 字符串必须使用双引号，不能使用单引号");
    if (c === '/') fail("JSON 不支持注释");
    fail("此处需要 JSON 值（对象、数组、字符串、数字、true、false 或 null）");
  }
  try {
    value(0); space();
    if (i !== text.length) fail("JSON 值后存在多余内容");
  } catch (error) {
    if (typeof error.offset === 'number') return error;
  }
  return null;
};
