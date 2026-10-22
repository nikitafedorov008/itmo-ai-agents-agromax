import ts from 'typescript';
import {readFileSync} from 'node:fs';
export function domainSchemas(){
 const file=ts.createSourceFile('contracts.ts',readFileSync('packages/contracts/src/index.ts','utf8'),ts.ScriptTarget.Latest,true);
 function schema(n){
  if(!n)return {};
  if(ts.isParenthesizedTypeNode(n))return schema(n.type);
  if(ts.isArrayTypeNode(n))return {type:'array',items:schema(n.elementType)};
  if(ts.isLiteralTypeNode(n)){if(ts.isStringLiteral(n.literal))return {type:'string',enum:[n.literal.text]};if(n.literal.kind===ts.SyntaxKind.TrueKeyword)return {type:'boolean',enum:[true]};return {};}
  if(ts.isUnionTypeNode(n)){const parts=n.types.map(schema);if(parts.every(s=>s.enum&&s.type===parts[0].type))return {type:parts[0].type,enum:parts.flatMap(s=>s.enum)};return {oneOf:parts};}
  if(ts.isTypeReferenceNode(n)){const name=n.typeName.getText(file);if(name==='Record')return {type:'object',additionalProperties:schema(n.typeArguments?.[1])};return {$ref:'#/components/schemas/'+name};}
  if(ts.isTypeLiteralNode(n))return properties(n.members);
  return ({[ts.SyntaxKind.StringKeyword]:{type:'string'},[ts.SyntaxKind.NumberKeyword]:{type:'number'},[ts.SyntaxKind.BooleanKeyword]:{type:'boolean'},[ts.SyntaxKind.UnknownKeyword]:{}})[n.kind]||{};
 }
 function properties(members){const props={},required=[];for(const m of members){if(!ts.isPropertySignature(m))continue;const key=m.name.getText(file);props[key]=schema(m.type);if(!m.questionToken)required.push(key);}return {type:'object',properties:props,...(required.length?{required}:{}),additionalProperties:false};}
 const result={};for(const n of file.statements){if(ts.isInterfaceDeclaration(n))result[n.name.text]=properties(n.members);if(ts.isTypeAliasDeclaration(n))result[n.name.text]=schema(n.type);}return result;
}
