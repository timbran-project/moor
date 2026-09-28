// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

import { SemanticAnnotation } from "@moor/web-sdk";
import { createContext, useContext } from "react";

export interface AnnotationActivation {
    annotation: SemanticAnnotation;
    label: string;
    position: { x: number; y: number };
}

export const AnnotationContext = createContext<((activation: AnnotationActivation) => void) | null>(null);
export const useAnnotationActivation = () => useContext(AnnotationContext);
