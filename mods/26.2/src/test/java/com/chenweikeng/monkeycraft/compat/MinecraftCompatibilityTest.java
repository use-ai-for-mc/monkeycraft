package com.chenweikeng.monkeycraft.compat;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.objectweb.asm.Handle;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.AnnotationNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.FieldNode;
import org.objectweb.asm.tree.InvokeDynamicInsnNode;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.MultiANewArrayInsnNode;
import org.objectweb.asm.tree.TypeInsnNode;

class MinecraftCompatibilityTest {
  private static final String MIXIN = "Lorg/spongepowered/asm/mixin/Mixin;";
  private static final String PSEUDO = "Lorg/spongepowered/asm/mixin/Pseudo;";
  private static final String SHADOW = "Lorg/spongepowered/asm/mixin/Shadow;";
  private static final String ACCESSOR = "Lorg/spongepowered/asm/mixin/gen/Accessor;";
  private static final String INVOKER = "Lorg/spongepowered/asm/mixin/gen/Invoker;";
  private static final String INJECT = "Lorg/spongepowered/asm/mixin/injection/Inject;";
  private static final String AT = "Lorg/spongepowered/asm/mixin/injection/At;";
  private static final String CALLBACK_INFO =
      "Lorg/spongepowered/asm/mixin/injection/callback/CallbackInfo;";
  private static final String CALLBACK_INFO_RETURNABLE =
      "Lorg/spongepowered/asm/mixin/injection/callback/CallbackInfoReturnable;";
  private static final Set<String> INJECTION_ANNOTATIONS =
      Set.of(
          INJECT,
          "Lorg/spongepowered/asm/mixin/injection/Redirect;",
          "Lorg/spongepowered/asm/mixin/injection/ModifyArg;",
          "Lorg/spongepowered/asm/mixin/injection/ModifyArgs;",
          "Lorg/spongepowered/asm/mixin/injection/ModifyVariable;",
          "Lorg/spongepowered/asm/mixin/injection/ModifyConstant;",
          "Lcom/llamalad7/mixinextras/injector/ModifyExpressionValue;",
          "Lcom/llamalad7/mixinextras/injector/wrapoperation/WrapOperation;");
  private static final List<String> REQUIRED_RUNTIME_PREFIXES =
      List.of(
          "net/minecraft/",
          "net/fabricmc/",
          "com/mojang/blaze3d/",
          "com/mojang/authlib/",
          "com/mojang/brigadier/",
          "com/chenweikeng/monkeycraft_api/",
          "me/shedaniel/clothconfig2/",
          "org/java_websocket/",
          "org/jcodec/",
          "com/google/gson/",
          "com/google/zxing/",
          "org/lwjgl/",
          "org/joml/",
          "org/slf4j/");
  private static final ClassLoader LOADER = MinecraftCompatibilityTest.class.getClassLoader();
  private static final Map<String, Optional<ClassNode>> CLASS_CACHE = new HashMap<>();

  @Test
  void validatesEveryMixinRegisteredByTheRealConfiguration() throws Exception {
    MixinConfiguration configuration = readMixinConfiguration();
    ValidationReport report = new ValidationReport();
    List<String> failures = new ArrayList<>();

    assertFalse(configuration.mixinClasses().isEmpty(), "Mixin configuration is empty");
    for (String mixinClass : configuration.mixinClasses()) {
      validateMixin(mixinClass, report, failures);
    }

    assertEquals(
        configuration.mixinClasses().size(),
        report.validatedMixins,
        "Not every registered Mixin participated in validation");
    assertTrue(failures.isEmpty(), () -> String.join(System.lineSeparator(), failures));
    System.out.printf(
        "Validated %d Mixins, %d injection selectors, %d shadow/accessor fields, "
            + "%d shadow/invoker methods, and %d explicit @At member targets.%n",
        report.validatedMixins,
        report.injectionSelectors,
        report.fields,
        report.methods,
        report.atTargets);
  }

  @Test
  void resolvesAllRequiredBytecodeReferencesAgainstTheExactRuntimeClasspath() throws Exception {
    List<String> failures = new ArrayList<>();
    int references = 0;
    for (ClassNode source : readMainClasses()) {
      references += validateRequiredRuntimeReferences(source, failures);
    }
    assertTrue(failures.isEmpty(), () -> String.join(System.lineSeparator(), failures));
    assertTrue(references > 0, "No required runtime bytecode references were inspected");
    System.out.printf(
        "Validated %d required runtime method, field, and type bytecode references.%n", references);
  }

  @Test
  void keepsOptionalModMenuTypesOutOfTheRequiredEntrypoint() throws Exception {
    JsonObject metadata = readJson("fabric.mod.json");
    assertTrue(metadata.getAsJsonObject("suggests").has("modmenu"));
    assertFalse(metadata.getAsJsonObject("depends").has("modmenu"));
    assertEquals(
        ">=26.2.155", metadata.getAsJsonObject("depends").get("cloth-config").getAsString());
    assertNull(
        LOADER.getResource("com/terraformersmc/modmenu/api/ModMenuApi.class"),
        "The optional ModMenu API unexpectedly leaked onto test runtime classpath");

    List<String> offenders = new ArrayList<>();
    for (ClassNode source : readMainClasses()) {
      if (source.name.endsWith("/integration/ModMenuIntegration")) {
        continue;
      }
      collectReferencedTypes(source).stream()
          .filter(name -> name.startsWith("com/terraformersmc/modmenu/"))
          .forEach(name -> offenders.add(source.name + " -> " + name));
    }

    assertTrue(
        offenders.isEmpty(),
        () -> "Required Monkeycraft classes reference optional ModMenu types: " + offenders);
    Class.forName("com.chenweikeng.monkeycraft.MonkeycraftClient", false, LOADER);
  }

  @Test
  void preservesReleaseMetadataAndProtocolV2() throws Exception {
    JsonObject metadata = readJson("fabric.mod.json");
    assertEquals("monkeycraft", metadata.get("id").getAsString());
    assertEquals("1.4.2-26.2", metadata.get("version").getAsString());
    assertEquals("client", metadata.get("environment").getAsString());
    assertEquals("~26.2", metadata.getAsJsonObject("depends").get("minecraft").getAsString());
    assertEquals(">=25", metadata.getAsJsonObject("depends").get("java").getAsString());
    assertEquals("monkeycraft.mixins.json", metadata.getAsJsonArray("mixins").get(0).getAsString());

    ClassNode authenticationHandler =
        loadClass("com/chenweikeng/monkeycraft/server/handler/AuthenticationHandler").orElseThrow();
    FieldNode protocolVersion =
        authenticationHandler.fields.stream()
            .filter(field -> field.name.equals("PROTOCOL_VERSION") && field.desc.equals("I"))
            .findFirst()
            .orElseThrow();
    assertEquals(2, protocolVersion.value);
    assertTrue((protocolVersion.access & Opcodes.ACC_STATIC) != 0);
    assertTrue((protocolVersion.access & Opcodes.ACC_FINAL) != 0);
  }

  private static void validateMixin(
      String mixinClass, ValidationReport report, List<String> failures) throws IOException {
    ClassNode mixin = loadClass(mixinClass).orElse(null);
    if (mixin == null) {
      failures.add("Registered Mixin class is missing: " + mixinClass);
      return;
    }

    AnnotationNode mixinAnnotation = findAnnotation(mixin, MIXIN);
    if (mixinAnnotation == null) {
      failures.add("Registered class has no @Mixin annotation: " + mixinClass);
      return;
    }

    boolean pseudo = findAnnotation(mixin, PSEUDO) != null;
    List<String> targets = mixinTargets(mixinAnnotation);
    if (targets.isEmpty()) {
      failures.add("@Mixin has no target: " + mixinClass);
      return;
    }

    for (String targetName : targets) {
      Optional<ClassNode> target = loadClass(targetName);
      if (target.isEmpty()) {
        if (pseudo) {
          report.skippedPseudoTargets++;
          continue;
        }
        failures.add(mixinClass + " targets missing class " + targetName);
        continue;
      }
      validateMixinMembers(mixin, target.get(), report, failures);
    }
    report.validatedMixins++;
  }

  private static void validateMixinMembers(
      ClassNode mixin, ClassNode target, ValidationReport report, List<String> failures)
      throws IOException {
    for (FieldNode field : mixin.fields) {
      if (findAnnotation(field, SHADOW) == null) {
        continue;
      }
      report.fields++;
      FieldNode targetField = resolveField(target.name, field.name, field.desc, new HashSet<>());
      if (targetField == null) {
        failures.add(memberFailure(mixin, target, "@Shadow field", field.name, field.desc));
      } else if (isStatic(field.access) != isStatic(targetField.access)) {
        failures.add(
            memberFailure(mixin, target, "@Shadow field staticness", field.name, field.desc));
      }
    }

    for (MethodNode method : mixin.methods) {
      AnnotationNode shadow = findAnnotation(method, SHADOW);
      if (shadow != null) {
        report.methods++;
        MethodNode targetMethod =
            resolveMethod(target.name, method.name, method.desc, new HashSet<>());
        if (targetMethod == null) {
          failures.add(memberFailure(mixin, target, "@Shadow method", method.name, method.desc));
        } else if (isStatic(method.access) != isStatic(targetMethod.access)) {
          failures.add(
              memberFailure(mixin, target, "@Shadow method staticness", method.name, method.desc));
        }
      }

      AnnotationNode accessor = findAnnotation(method, ACCESSOR);
      if (accessor != null) {
        report.fields++;
        validateAccessor(mixin, target, method, accessor, failures);
      }

      AnnotationNode invoker = findAnnotation(method, INVOKER);
      if (invoker != null) {
        report.methods++;
        validateInvoker(mixin, target, method, invoker, failures);
      }

      for (AnnotationNode annotation : annotations(method)) {
        if (!INJECTION_ANNOTATIONS.contains(annotation.desc)) {
          continue;
        }
        List<String> selectors = stringValues(annotationValue(annotation, "method"));
        if (selectors.isEmpty()) {
          failures.add(
              mixin.name + " injection handler " + method.name + " has no method selector");
        }
        for (String selector : selectors) {
          report.injectionSelectors++;
          MethodNode injectedMethod =
              resolveInjectionTarget(target, selector, mixin, method, failures);
          if (injectedMethod != null && annotation.desc.equals(INJECT)) {
            validateInjectHandler(mixin, target, method, injectedMethod, failures);
          }
        }
        for (AnnotationNode at : nestedAnnotations(annotation, AT)) {
          String atTarget = stringValue(annotationValue(at, "target"));
          if (atTarget != null && !atTarget.isBlank()) {
            report.atTargets++;
            validateAtTarget(mixin, method, atTarget, failures);
          }
        }
      }
    }
  }

  private static void validateAccessor(
      ClassNode mixin,
      ClassNode target,
      MethodNode accessor,
      AnnotationNode annotation,
      List<String> failures)
      throws IOException {
    String fieldName = stringValue(annotationValue(annotation, "value"));
    if (fieldName == null || fieldName.isBlank()) {
      fieldName = inferredAccessorName(accessor.name);
    }
    Type methodType = Type.getMethodType(accessor.desc);
    Type[] arguments = methodType.getArgumentTypes();
    Type returnType = methodType.getReturnType();
    String fieldDescriptor;
    if (arguments.length == 0 && returnType.getSort() != Type.VOID) {
      fieldDescriptor = returnType.getDescriptor();
    } else if (arguments.length == 1 && returnType.getSort() == Type.VOID) {
      fieldDescriptor = arguments[0].getDescriptor();
    } else {
      failures.add(
          memberFailure(
              mixin, target, "invalid @Accessor signature", accessor.name, accessor.desc));
      return;
    }
    if (fieldName == null
        || resolveField(target.name, fieldName, fieldDescriptor, new HashSet<>()) == null) {
      failures.add(memberFailure(mixin, target, "@Accessor field", fieldName, fieldDescriptor));
    }
  }

  private static void validateInvoker(
      ClassNode mixin,
      ClassNode target,
      MethodNode invoker,
      AnnotationNode annotation,
      List<String> failures)
      throws IOException {
    String methodName = stringValue(annotationValue(annotation, "value"));
    if (methodName == null || methodName.isBlank()) {
      methodName = inferredInvokerName(invoker.name);
    }
    MethodNode targetMethod =
        methodName == null
            ? null
            : resolveMethod(target.name, methodName, invoker.desc, new HashSet<>());
    if (targetMethod == null) {
      failures.add(memberFailure(mixin, target, "@Invoker method", methodName, invoker.desc));
    } else if (isStatic(invoker.access) != isStatic(targetMethod.access)) {
      failures.add(memberFailure(mixin, target, "@Invoker staticness", methodName, invoker.desc));
    }
  }

  private static MethodNode resolveInjectionTarget(
      ClassNode target,
      String selector,
      ClassNode mixin,
      MethodNode handler,
      List<String> failures) {
    MethodSelector parsed = MethodSelector.parse(selector);
    if (parsed == null) {
      failures.add(
          mixin.name + " handler " + handler.name + " has unsupported selector " + selector);
      return null;
    }
    if (parsed.owner() != null && !parsed.owner().equals(target.name)) {
      failures.add(
          mixin.name
              + " handler "
              + handler.name
              + " selector owner "
              + parsed.owner()
              + " does not match "
              + target.name);
      return null;
    }
    if (parsed.descriptor() != null) {
      return target.methods.stream()
          .filter(
              method ->
                  method.name.equals(parsed.name()) && method.desc.equals(parsed.descriptor()))
          .findFirst()
          .orElseGet(
              () -> {
                failures.add(
                    memberFailure(
                        mixin, target, "injection target", parsed.name(), parsed.descriptor()));
                return null;
              });
    }
    List<MethodNode> candidates =
        target.methods.stream().filter(method -> method.name.equals(parsed.name())).toList();
    if (candidates.size() != 1) {
      failures.add(
          mixin.name
              + " handler "
              + handler.name
              + " selector "
              + selector
              + " resolved to "
              + candidates.size()
              + " methods in "
              + target.name);
      return null;
    }
    return candidates.getFirst();
  }

  private static void validateInjectHandler(
      ClassNode mixin,
      ClassNode target,
      MethodNode handler,
      MethodNode injectedMethod,
      List<String> failures) {
    Type[] targetArguments = Type.getArgumentTypes(injectedMethod.desc);
    Type[] handlerArguments = Type.getArgumentTypes(handler.desc);
    String expectedCallback =
        Type.getReturnType(injectedMethod.desc).getSort() == Type.VOID
            ? CALLBACK_INFO
            : CALLBACK_INFO_RETURNABLE;
    if (handlerArguments.length != targetArguments.length + 1) {
      failures.add(
          memberFailure(
              mixin,
              target,
              "@Inject handler argument count for " + injectedMethod.name + injectedMethod.desc,
              handler.name,
              handler.desc));
      return;
    }
    for (int index = 0; index < targetArguments.length; index++) {
      if (!handlerArguments[index].equals(targetArguments[index])) {
        failures.add(
            memberFailure(
                mixin,
                target,
                "@Inject handler argument " + index + " for " + injectedMethod.name,
                handler.name,
                handler.desc));
      }
    }
    if (!handlerArguments[targetArguments.length].getDescriptor().equals(expectedCallback)) {
      failures.add(
          memberFailure(
              mixin,
              target,
              "@Inject callback for " + injectedMethod.name + injectedMethod.desc,
              handler.name,
              handler.desc));
    }
    if (Type.getReturnType(handler.desc).getSort() != Type.VOID) {
      failures.add(
          memberFailure(mixin, target, "@Inject handler return", handler.name, handler.desc));
    }
    if (isStatic(handler.access) != isStatic(injectedMethod.access)) {
      failures.add(
          memberFailure(mixin, target, "@Inject handler staticness", handler.name, handler.desc));
    }
  }

  private static void validateAtTarget(
      ClassNode mixin, MethodNode handler, String target, List<String> failures)
      throws IOException {
    MemberReference reference = MemberReference.parse(target);
    if (reference == null) {
      failures.add(
          mixin.name + " handler " + handler.name + " has unsupported @At target " + target);
      return;
    }
    if (reference.method()) {
      if (resolveMethod(
              reference.owner(), reference.name(), reference.descriptor(), new HashSet<>())
          == null) {
        failures.add(mixin.name + " handler " + handler.name + " missing @At method " + target);
      }
    } else if (resolveField(
            reference.owner(), reference.name(), reference.descriptor(), new HashSet<>())
        == null) {
      failures.add(mixin.name + " handler " + handler.name + " missing @At field " + target);
    }
  }

  private static int validateRequiredRuntimeReferences(ClassNode source, List<String> failures)
      throws IOException {
    int references = 0;
    for (FieldNode field : source.fields) {
      references += validateTypes(source.name, field.desc, failures);
    }
    for (MethodNode method : source.methods) {
      references += validateTypes(source.name, method.desc, failures);
      for (AbstractInsnNode instruction : method.instructions) {
        if (instruction instanceof MethodInsnNode call && isRequiredRuntimeType(call.owner)) {
          references++;
          if (resolveMethod(call.owner, call.name, call.desc, new HashSet<>()) == null) {
            failures.add(
                source.name
                    + "#"
                    + method.name
                    + method.desc
                    + " references missing method "
                    + call.owner
                    + "#"
                    + call.name
                    + call.desc);
          }
        } else if (instruction instanceof FieldInsnNode access
            && isRequiredRuntimeType(access.owner)) {
          references++;
          if (resolveField(access.owner, access.name, access.desc, new HashSet<>()) == null) {
            failures.add(
                source.name
                    + "#"
                    + method.name
                    + method.desc
                    + " references missing field "
                    + access.owner
                    + "#"
                    + access.name
                    + ":"
                    + access.desc);
          }
        } else if (instruction instanceof TypeInsnNode type && isRequiredRuntimeType(type.desc)) {
          references++;
          validateClassExists(source.name, type.desc, failures);
        } else if (instruction instanceof MultiANewArrayInsnNode array) {
          references += validateTypes(source.name, array.desc, failures);
        } else if (instruction instanceof LdcInsnNode constant
            && constant.cst instanceof Type type) {
          references += validateType(source.name, type, failures);
        } else if (instruction instanceof InvokeDynamicInsnNode dynamic) {
          references += validateTypes(source.name, dynamic.desc, failures);
          for (Object argument : dynamic.bsmArgs) {
            if (argument instanceof Type type) {
              references += validateType(source.name, type, failures);
            } else if (argument instanceof Handle handle
                && isRequiredRuntimeType(handle.getOwner())) {
              references++;
              if (handle.getTag() <= Opcodes.H_PUTSTATIC) {
                if (resolveField(
                        handle.getOwner(), handle.getName(), handle.getDesc(), new HashSet<>())
                    == null) {
                  failures.add(source.name + " references missing bootstrap field " + handle);
                }
              } else if (resolveMethod(
                      handle.getOwner(), handle.getName(), handle.getDesc(), new HashSet<>())
                  == null) {
                failures.add(source.name + " references missing bootstrap method " + handle);
              }
            }
          }
        }
      }
    }
    return references;
  }

  private static int validateTypes(String source, String descriptor, List<String> failures)
      throws IOException {
    Type type =
        descriptor.startsWith("(") ? Type.getMethodType(descriptor) : Type.getType(descriptor);
    int references = 0;
    if (type.getSort() == Type.METHOD) {
      for (Type argument : type.getArgumentTypes()) {
        references += validateType(source, argument, failures);
      }
      references += validateType(source, type.getReturnType(), failures);
    } else {
      references += validateType(source, type, failures);
    }
    return references;
  }

  private static int validateType(String source, Type type, List<String> failures)
      throws IOException {
    while (type.getSort() == Type.ARRAY) {
      type = type.getElementType();
    }
    if (type.getSort() != Type.OBJECT || !isRequiredRuntimeType(type.getInternalName())) {
      return 0;
    }
    validateClassExists(source, type.getInternalName(), failures);
    return 1;
  }

  private static void validateClassExists(String source, String target, List<String> failures)
      throws IOException {
    if (loadClass(target).isEmpty()) {
      failures.add(source + " references missing class " + target);
    }
  }

  private static MethodNode resolveMethod(
      String owner, String name, String descriptor, Set<String> visited) throws IOException {
    if (owner == null || !visited.add(owner)) {
      return null;
    }
    ClassNode type = loadClass(owner).orElse(null);
    if (type == null) {
      return null;
    }
    for (MethodNode method : type.methods) {
      if (method.name.equals(name) && method.desc.equals(descriptor)) {
        return method;
      }
    }
    MethodNode inherited = resolveMethod(type.superName, name, descriptor, visited);
    if (inherited != null) {
      return inherited;
    }
    for (String interfaceName : type.interfaces) {
      inherited = resolveMethod(interfaceName, name, descriptor, visited);
      if (inherited != null) {
        return inherited;
      }
    }
    return null;
  }

  private static FieldNode resolveField(
      String owner, String name, String descriptor, Set<String> visited) throws IOException {
    if (owner == null || !visited.add(owner)) {
      return null;
    }
    ClassNode type = loadClass(owner).orElse(null);
    if (type == null) {
      return null;
    }
    for (FieldNode field : type.fields) {
      if (field.name.equals(name) && field.desc.equals(descriptor)) {
        return field;
      }
    }
    FieldNode inherited = resolveField(type.superName, name, descriptor, visited);
    if (inherited != null) {
      return inherited;
    }
    for (String interfaceName : type.interfaces) {
      inherited = resolveField(interfaceName, name, descriptor, visited);
      if (inherited != null) {
        return inherited;
      }
    }
    return null;
  }

  private static Optional<ClassNode> loadClass(String internalName) throws IOException {
    if (internalName == null) {
      return Optional.empty();
    }
    Optional<ClassNode> cached = CLASS_CACHE.get(internalName);
    if (cached != null) {
      return cached;
    }
    try (InputStream input = LOADER.getResourceAsStream(internalName + ".class")) {
      if (input == null) {
        Optional<ClassNode> missing = Optional.empty();
        CLASS_CACHE.put(internalName, missing);
        return missing;
      }
      ClassNode node = new ClassNode();
      new org.objectweb.asm.ClassReader(input)
          .accept(
              node,
              org.objectweb.asm.ClassReader.SKIP_DEBUG | org.objectweb.asm.ClassReader.SKIP_FRAMES);
      Optional<ClassNode> loaded = Optional.of(node);
      CLASS_CACHE.put(internalName, loaded);
      return loaded;
    }
  }

  private static List<ClassNode> readMainClasses() throws Exception {
    String marker = "com/chenweikeng/monkeycraft/MonkeycraftClient.class";
    URL markerUrl = LOADER.getResource(marker);
    assertNotNull(markerUrl, "Main classes are unavailable");
    URI markerUri = markerUrl.toURI();
    assertEquals(
        "file", markerUri.getScheme(), "Main test classes must be loaded from a directory");
    Path markerPath = Path.of(markerUri);
    Path root = markerPath;
    for (int index = 0; index < marker.split("/").length; index++) {
      root = root.getParent();
    }
    Path packageRoot = root.resolve("com/chenweikeng/monkeycraft");
    List<ClassNode> classes = new ArrayList<>();
    try (var files = Files.walk(packageRoot)) {
      for (Path path : files.filter(file -> file.toString().endsWith(".class")).toList()) {
        String internalName =
            root.relativize(path).toString().replace(path.getFileSystem().getSeparator(), "/");
        internalName = internalName.substring(0, internalName.length() - ".class".length());
        classes.add(loadClass(internalName).orElseThrow());
      }
    }
    return classes;
  }

  private static Set<String> collectReferencedTypes(ClassNode source) {
    Set<String> types = new HashSet<>();
    collectType(types, Type.getObjectType(source.name));
    if (source.superName != null) {
      types.add(source.superName);
    }
    types.addAll(source.interfaces);
    for (FieldNode field : source.fields) {
      collectDescriptorTypes(types, field.desc);
    }
    for (MethodNode method : source.methods) {
      collectDescriptorTypes(types, method.desc);
      for (AbstractInsnNode instruction : method.instructions) {
        if (instruction instanceof MethodInsnNode call) {
          types.add(call.owner);
          collectDescriptorTypes(types, call.desc);
        } else if (instruction instanceof FieldInsnNode field) {
          types.add(field.owner);
          collectDescriptorTypes(types, field.desc);
        } else if (instruction instanceof TypeInsnNode type) {
          types.add(type.desc);
        } else if (instruction instanceof LdcInsnNode constant
            && constant.cst instanceof Type type) {
          collectType(types, type);
        }
      }
    }
    return types;
  }

  private static void collectDescriptorTypes(Set<String> types, String descriptor) {
    Type type =
        descriptor.startsWith("(") ? Type.getMethodType(descriptor) : Type.getType(descriptor);
    if (type.getSort() == Type.METHOD) {
      for (Type argument : type.getArgumentTypes()) {
        collectType(types, argument);
      }
      collectType(types, type.getReturnType());
    } else {
      collectType(types, type);
    }
  }

  private static void collectType(Set<String> types, Type type) {
    while (type.getSort() == Type.ARRAY) {
      type = type.getElementType();
    }
    if (type.getSort() == Type.OBJECT) {
      types.add(type.getInternalName());
    }
  }

  private static MixinConfiguration readMixinConfiguration() throws IOException {
    JsonObject json = readJson("monkeycraft.mixins.json");
    String packageName = json.get("package").getAsString();
    List<String> classes = new ArrayList<>();
    for (String key : List.of("mixins", "client", "server")) {
      JsonArray values = json.getAsJsonArray(key);
      if (values == null) {
        continue;
      }
      for (JsonElement value : values) {
        classes.add((packageName + "." + value.getAsString()).replace('.', '/'));
      }
    }
    return new MixinConfiguration(classes);
  }

  private static JsonObject readJson(String resource) throws IOException {
    try (InputStream input = LOADER.getResourceAsStream(resource)) {
      assertNotNull(input, "Missing test resource " + resource);
      return JsonParser.parseString(
              new String(input.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8))
          .getAsJsonObject();
    }
  }

  private static List<String> mixinTargets(AnnotationNode annotation) {
    List<String> targets = new ArrayList<>();
    Object values = annotationValue(annotation, "value");
    if (values instanceof List<?> list) {
      for (Object value : list) {
        if (value instanceof Type type) {
          targets.add(type.getInternalName());
        }
      }
    }
    Object strings = annotationValue(annotation, "targets");
    if (strings instanceof List<?> list) {
      for (Object value : list) {
        if (value instanceof String string) {
          targets.add(string.replace('.', '/'));
        }
      }
    }
    return targets;
  }

  private static List<AnnotationNode> annotations(ClassNode node) {
    return merge(node.visibleAnnotations, node.invisibleAnnotations);
  }

  private static List<AnnotationNode> annotations(MethodNode node) {
    return merge(node.visibleAnnotations, node.invisibleAnnotations);
  }

  private static List<AnnotationNode> annotations(FieldNode node) {
    return merge(node.visibleAnnotations, node.invisibleAnnotations);
  }

  private static List<AnnotationNode> merge(
      List<AnnotationNode> visible, List<AnnotationNode> invisible) {
    List<AnnotationNode> result = new ArrayList<>();
    if (visible != null) {
      result.addAll(visible);
    }
    if (invisible != null) {
      result.addAll(invisible);
    }
    return result;
  }

  private static AnnotationNode findAnnotation(ClassNode node, String descriptor) {
    return annotations(node).stream()
        .filter(annotation -> annotation.desc.equals(descriptor))
        .findFirst()
        .orElse(null);
  }

  private static AnnotationNode findAnnotation(MethodNode node, String descriptor) {
    return annotations(node).stream()
        .filter(annotation -> annotation.desc.equals(descriptor))
        .findFirst()
        .orElse(null);
  }

  private static AnnotationNode findAnnotation(FieldNode node, String descriptor) {
    return annotations(node).stream()
        .filter(annotation -> annotation.desc.equals(descriptor))
        .findFirst()
        .orElse(null);
  }

  private static Object annotationValue(AnnotationNode annotation, String name) {
    if (annotation.values == null) {
      return null;
    }
    for (int index = 0; index < annotation.values.size(); index += 2) {
      if (annotation.values.get(index).equals(name)) {
        return annotation.values.get(index + 1);
      }
    }
    return null;
  }

  private static List<String> stringValues(Object value) {
    if (value instanceof String string) {
      return List.of(string);
    }
    if (value instanceof List<?> list) {
      return list.stream().filter(String.class::isInstance).map(String.class::cast).toList();
    }
    return List.of();
  }

  private static String stringValue(Object value) {
    return value instanceof String string ? string : null;
  }

  private static List<AnnotationNode> nestedAnnotations(
      AnnotationNode annotation, String descriptor) {
    List<AnnotationNode> result = new ArrayList<>();
    collectNestedAnnotations(annotation.values, descriptor, result);
    return result;
  }

  private static void collectNestedAnnotations(
      Object value, String descriptor, List<AnnotationNode> result) {
    if (value instanceof AnnotationNode annotation) {
      if (annotation.desc.equals(descriptor)) {
        result.add(annotation);
      }
      collectNestedAnnotations(annotation.values, descriptor, result);
    } else if (value instanceof List<?> list) {
      for (Object element : list) {
        collectNestedAnnotations(element, descriptor, result);
      }
    }
  }

  private static String inferredAccessorName(String name) {
    for (String prefix : List.of("get", "is", "set")) {
      if (name.startsWith(prefix) && name.length() > prefix.length()) {
        return decapitalize(name.substring(prefix.length()));
      }
    }
    return null;
  }

  private static String inferredInvokerName(String name) {
    for (String prefix : List.of("call", "invoke")) {
      if (name.startsWith(prefix) && name.length() > prefix.length()) {
        return decapitalize(name.substring(prefix.length()));
      }
    }
    return null;
  }

  private static String decapitalize(String value) {
    return Character.toLowerCase(value.charAt(0)) + value.substring(1);
  }

  private static boolean isRequiredRuntimeType(String internalName) {
    return internalName != null
        && REQUIRED_RUNTIME_PREFIXES.stream().anyMatch(internalName::startsWith);
  }

  private static boolean isStatic(int access) {
    return (access & Opcodes.ACC_STATIC) != 0;
  }

  private static String memberFailure(
      ClassNode mixin, ClassNode target, String kind, String name, String descriptor) {
    return mixin.name
        + " -> "
        + target.name
        + " missing or incompatible "
        + kind
        + " "
        + name
        + descriptor;
  }

  private record MixinConfiguration(List<String> mixinClasses) {}

  private record MethodSelector(String owner, String name, String descriptor) {
    private static MethodSelector parse(String selector) {
      String owner = null;
      String member = selector;
      if (selector.startsWith("L")) {
        int separator = selector.indexOf(';');
        if (separator < 0) {
          return null;
        }
        owner = selector.substring(1, separator);
        member = selector.substring(separator + 1);
      }
      int descriptorStart = member.indexOf('(');
      if (descriptorStart < 0) {
        return member.isBlank() ? null : new MethodSelector(owner, member, null);
      }
      return new MethodSelector(
          owner, member.substring(0, descriptorStart), member.substring(descriptorStart));
    }
  }

  private record MemberReference(String owner, String name, String descriptor, boolean method) {
    private static MemberReference parse(String value) {
      if (!value.startsWith("L")) {
        return null;
      }
      int separator = value.indexOf(';');
      if (separator < 0) {
        return null;
      }
      String owner = value.substring(1, separator);
      String member = value.substring(separator + 1);
      int methodDescriptor = member.indexOf('(');
      if (methodDescriptor >= 0) {
        return new MemberReference(
            owner, member.substring(0, methodDescriptor), member.substring(methodDescriptor), true);
      }
      int fieldDescriptor = member.indexOf(':');
      if (fieldDescriptor < 0) {
        return null;
      }
      return new MemberReference(
          owner,
          member.substring(0, fieldDescriptor),
          member.substring(fieldDescriptor + 1),
          false);
    }
  }

  private static final class ValidationReport {
    private int validatedMixins;
    private int injectionSelectors;
    private int fields;
    private int methods;
    private int atTargets;
    private int skippedPseudoTargets;
  }
}
