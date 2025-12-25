import src/kdl

try:
  let doc = parseKdl("node 0")
  echo "Parsed successfully:"
  echo doc.pretty()
except Exception as e:
  echo "Error: ", e.msg
